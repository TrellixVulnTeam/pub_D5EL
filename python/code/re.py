#!/usr/bin/python

import re

# 将匹配的数字乘于 2
def double(matched):
	value = int(matched.group('value'))
	return str(value * 2)

s = 'A23G4HFD567'
print(re.sub('(?P<value>\d+)', double, s))
