##!/usr/bin/perl
#package Conf;
#require Exporter;

#@ISA=qw(Exporter);
#@EXPORT=qw(ret);
my %arr=(
	'a'=>{
			'name'=>'Tom',
			'age'=>'3',
	},
	'b'=>{
			'name'=>'Tom',
			'age'=>'3',
	},
);

sub ret{
	return \%arr;		
}

1;
