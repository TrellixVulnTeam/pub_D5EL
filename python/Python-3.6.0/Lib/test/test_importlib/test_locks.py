from . import util as test_util

init = test_util.import_importlib('importlib')

import sys
import unittest
import weakref

from test import support

try:
    import threading
except ImportError:
    threading = None
else:
    from test import lock_tests

if threading is not None:
    class ModuleLockAsRLockTests:
        locktype = classmethod(lambda cls: cls.LockType("some_lock"))

        # _is_owned() unsupported
        test__is_owned = None
        # acquire(blocking=False) unsupported
        test_try_acquire = None
        test_try_acquire_contended = None
        # `with` unsupported
        test_with = None
        # acquire(timeout=...) unsupported
        test_timeout = None
        # _release_save() unsupported
        test_release_save_unacquired = None
        # lock status in repr unsupported
        test_repr = None
        test_locked_repr = None

    LOCK_TYPES = {kind: splitinit._bootstrap._ModuleLock
                  for kind, splitinit in init.items()}

    (Frozen_ModuleLockAsRLockTests,
     Source_ModuleLockAsRLockTests
     ) = test_util.test_both(ModuleLockAsRLockTests, lock_tests.RLockTests,
                             LockType=LOCK_TYPES)
else:
    LOCK_TYPES = {}

    class Frozen_ModuleLockAsRLockTests(unittest.TestCase):
        pass

    class Source_ModuleLockAsRLockTests(unittest.TestCase):
        pass


if threading is not None:
    class DeadlockAvoidanceTests:

        def setUp(self):
            try:
                self.old_switchinterval = sys.getswitchinterval()
                sys.setswitchinterval(0.000001)
            except AttributeError:
                self.old_switchinterval = None

        def tearDown(self):
            if self.old_switchinterval is not None:
                sys.setswitchinterval(self.old_switchinterval)

        def run_deadlock_avoidance_test(self, create_deadlock):
            NLOCKS = 10
            locks = [self.LockType(str(i)) for i in range(NLOCKS)]
            pairs = [(locks[i], locks[(i+1)%NLOCKS]) for i in range(NLOCKS)]
            if create_deadlock:
                NTHREADS = NLOCKS
            else:
                NTHREADS = NLOCKS - 1
            barrier = threading.Barrier(NTHREADS)
            results = []

            def _acquire(lock):
                """Try to acquire the lock. Return True on success,
                False on deadlock."""
                try:
                    lock.acquire()
                except self.DeadlockError:
                    return False
                else:
                    return True

            def f():
                a, b = pairs.pop()
                ra = _acquire(a)
                barrier.wait()
                rb = _acquire(b)
                results.append((ra, rb))
                if rb:
                    b.release()
                if ra:
                    a.release()
            lock_tests.Bunch(f, NTHREADS).wait_for_finished()
            self.assertEqual(len(results), NTHREADS)
            return results

        def test_deadlock(self):
            results = self.run_deadlock_avoidance_test(True)
            # At least one of the threads detected a potential deadlock on its
            # second acquire() call.  It may be several of them, because the
            # deadlock avoidance mechanism is conservative.
            nb_deadlocks = results.count((True, False))
            self.assertGreaterEqual(nb_deadlocks, 1)
            self.assertEqual(results.count((True, True)), len(results) - nb_deadlocks)

        def test_no_deadlock(self):
            results = self.run_deadlock_avoidance_test(False)
            self.assertEqual(results.count((True, False)), 0)
            self.assertEqual(results.count((True, True)), len(results))


    DEADLOCK_ERRORS = {kind: splitinit._bootstrap._DeadlockError
                       for kind, splitinit in init.items()}

    (Frozen_DeadlockAvoidanceTests,
     Source_DeadlockAvoidanceTests
     ) = test_util.test_both(DeadlockAvoidanceTests,
                             LockType=LOCK_TYPES,
                             DeadlockError=DEADLOCK_ERRORS)
else:
    DEADLOCK_ERRORS = {}

    class Frozen_DeadlockAvoidanceTests(unittest.TestCase):
        pass

    class Source_DeadlockAvoidanceTests(unittest.TestCase):
        pass


class LifetimeTests:

    @property
    def bootstrap(self):
        return self.init._bootstrap

    def test_lock_lifetime(self):
        name = "xyzzy"
        self.assertNotIn(name, self.bootstrap._module_locks)
        lock = self.bootstrap._get_module_lock(name)
        self.assertIn(name, self.bootstrap._module_locks)
        wr = weakref.ref(lock)
        del lock
        support.gc_collect()
        self.assertNotIn(name, self.bootstrap._module_locks)
        self.assertIsNone(wr())

    def test_all_locks(self):
        support.gc_collect()
        self.assertEqual(0, len(self.bootstrap._module_locks),
                         self.bootstrap._module_locks)


(Frozen_LifetimeTests,
 Source_LifetimeTests
 ) = test_util.test_both(LifetimeTests, init=init)


@support.reap_threads
def test_main():
    support.run_unittest(Frozen_ModuleLockAsRLockTests,
                         Source_ModuleLockAsRLockTests,
                         Frozen_DeadlockAvoidanceTests,
                         Source_DeadlockAvoidanceTests,
                         Frozen_LifetimeTests,
                         Source_LifetimeTests)


if __name__ == '__main__':
    test_main()
