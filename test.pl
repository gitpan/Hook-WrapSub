# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

use lib 'lib';

BEGIN { $| = 1; print "1..2\n"; }
END {print "not ok 1\n" unless $loaded;}
use Hook::WrapSub qw( wrap_subs unwrap_subs );
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):


my $result = '';

sub foo { $result .= "foo(@_)\n" }

wrap_subs
  sub { $result .= "0B(@_)[@Hook::WrapSub::caller[5]]\n" },
  'foo',
  sub { $result .= "0A(@_)[@Hook::WrapSub::caller[5]]\n" }
  ;

$r = foo( "'0'" );

wrap_subs
  sub { $result .= "1B(@_)[@Hook::WrapSub::caller[5]]\n"; @_ = ("'X'"); },
  'foo',
  sub { $result .= "1A(@_)[@Hook::WrapSub::caller[5]]\n" }
  ;

@r = foo( "'1'" );

unwrap_subs 'foo' ;

foo( "'2'" );

unwrap_subs 'foo' ;

foo( "'3'" );


print $result eq <<EOF ? "ok 2\n" : "not ok 2\n";
0B('0')[0]
foo('0')
0A('0')[0]
1B('1')[1]
0B('X')[1]
foo('X')
0A('X')[1]
1A('X')[1]
0B('2')[]
foo('2')
0A('2')[]
foo('3')
EOF


