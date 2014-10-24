
package Hook::WrapSub;

use Exporter;
use Symbol;
use strict;
use vars qw( $VERSION @ISA @EXPORT @EXPORT_OK );


$VERSION = '0.02';
@ISA = qw(Exporter);
@EXPORT = qw();
@EXPORT_OK = qw(
  wrap_subs
  unwrap_subs
);


=head1 NAME

Hook::WrapSub - wrap subs with pre- and post-call hooks

=head1 SYNOPSIS

  use Hook::WrapSub qw( wrap_subs unwrap_subs );

  wrap_subs \&before, 'some_func', 'another_func', \&after;

  unwrap_subs 'some_func';


=head1 DESCRIPTION

=head2 wrap_subs

This function enables intercepting a call to any named
function; handlers may be added both before and after
the call to the intercepted function.

For example:

  wrap_subs \&before, 'some_func', \&after;

In this case, whenever the sub named 'some_func' is called,
the &before sub is called first, and the &after sub is called
afterwards.  These are both optional.  If you only want
to intercept the call beforehand:

  wrap_subs \&before, 'some_func';

You may pass more than one sub name:

  wrap_subs \&before, 'foo', 'bar', 'baz', \&after;

and each one will have the same hooks applied.

The sub names may be qualified.  Any unqualified names
are assumed to reside in the package of the caller.

The &before sub and the &after sub are both passed the
argument list which is destined for the wrapped sub.
This can be inspected, and even altered, in the &before
sub:

  sub before {  
    ref($_[1]) && $_[1] =~ /\bARRAY\b/
      or croak "2nd arg must be an array-ref!";
    @_ or @_ = qw( default values );
    # if no args passed, insert some default values
  }

The &after sub is also passed this list.  Modifications
to it will (obviously) not be seen by the wrapped sub,
but the caller will see the changes, if it happens to
be looking.

Here's an example that causes a certain method call
to be redirected to a specific object.  (Note, we 
use splice to change $_[0], because assigning directly
to $_[0] would cause the change to be visible to the caller,
due to the magical aliasing nature of @_.)

  my $handler_object = new MyClass;

  Hook::WrapSub::wrap_subs
    sub { splice @_, 0, 1, $handler_object },
    'MyClass::some_method';
      
  my $other_object = new MyClass;
  $other_object->some_method;

  # even though the method is invoked on
  # $other_object, it will actually be executed
  # with a 0'th argument = $handler_obj,
  # as arranged by the pre-call hook sub.

=head2 Package Variables

There are some Hook::WrapSub package variables defined,
which the &before and &after subs may inspect.

=over 4

=item $Hook::WrapSub::name 

This is the fully qualified name of the wrapped sub.

=item @Hook::WrapSub::caller

This is a list which strongly resembles the result of a
call to the built-in function C<caller>; it is provided
because calling C<caller> will in fact produce confusing
results; if your sub is inclined to call C<caller>,
have it look at this variable instead.

=item @Hook::WrapSub::result

This contains the result of the call to the wrapped sub.
It is empty in the &before sub.  In the &after sub, it
will be empty if the sub was called in a void context,
it will contain one value if the sub was called in a
scalar context; otherwise, it may have any number of
elements.  Note that the &after function is not prevented
from modifying the contents of this array; any such
modifications will be seen by the caller!


=back

This simple example shows how Hook::WrapSub can be
used to log certain subroutine calls:

  sub before {
    print STDERR <<"    EOF";
      About to call $Hook::WrapSub::name( @_ );
      Wantarray=$Hook::WrapSub::caller[5]
    EOF
  }

  sub after {
    print STDERR <<"    EOF";
      Called $Hook::WrapSub::name( @_ );
      Result=( @Hook::WrapSub::result )
    EOF
    @Hook::WrapSub::result 
      or @Hook::WrapSub::result = qw( default return );
    # if the sub failed to return something...
  }

Much more elaborate uses are possible.  Here's one
one way it could be used with database operations:

  my $dbh; # initialized elsewhere.

  wrap_subs
    sub {
      $dbh->checkpoint
    },

    'MyDb::update',
    'MyDb::delete',

    sub {
      # examine result of sub call:
      if ( $Hook::WrapSub::result[0] ) {
        # success
        $dbh->commit;
      }
      else {
        # failure
        $dbh->rollback;
      }
    };

=head2  unwrap_subs

This removes the most recent wrapping of the named subs.

NOTE: Any given sub may be wrapped an unlimited
number of times.  A "stack" of the wrappings is
maintained internally.  wrap_subs "pushes" a wrapping,
and unwrap_subs "pops".

=cut

sub wrap_subs(@) {
  my( $precall_cr, $postcall_cr );
  ref($_[0]) and $precall_cr = shift;
  ref($_[-1]) and $postcall_cr = pop;
  my @names = @_;

  my( $calling_package ) = caller;

  for my $name ( @names ) {

    my $fullname;
    my $sr = *{ qualify_to_ref($name,$calling_package) }{CODE};
    if ( defined $sr ) { 
      $fullname = qualify($name,$calling_package);
    }
    else {
      warn "Can't find subroutine named '$name'\n";
      next;
    }


    my $cr = sub {
      $Hook::WrapSub::UNWRAP and return $sr;

#
# this is a bunch of kludg to make a list of values
# that look like a "real" caller() result.
#
      my $up = 0;
      my @args = caller($up);
      while ( $args[0] =~ /Hook::WrapSub/ ) {
        $up++;
        @args = caller($up);
      }
      my @vargs = @args; # save temp
      while ( $args[3] =~ /Hook::WrapSub/ ) {
        $up++;
        @args = caller($up);
      }
      $vargs[3] = $args[3];
      # now @vargs looks right.

      local $Hook::WrapSub::name = $fullname;
      local @Hook::WrapSub::result = ();
      local @Hook::WrapSub::caller = @vargs;
      my $wantarray = $Hook::WrapSub::caller[5];
#
# try to supply the same calling context to the nested sub:
#

      unless ( defined $wantarray ) {
        # void context
        &$precall_cr  if $precall_cr;
        &$sr;
        &$postcall_cr if $postcall_cr;
        return();
      }

      if ( $wantarray ) {
        # scalar context
        &$precall_cr  if $precall_cr;
        $Hook::WrapSub::result[0] = &$sr;
        &$postcall_cr if $postcall_cr;
        return $Hook::WrapSub::result[0];
      }

      # list context
      &$precall_cr  if $precall_cr;
      @Hook::WrapSub::result = &$sr;
      &$postcall_cr if $postcall_cr;
      return( @Hook::WrapSub::result );
    };

    $^W = 0;
    no strict 'refs';
    *{ $fullname } = $cr;
  }
}

sub unwrap_subs(@) {
  my @names = @_;

  my( $calling_package ) = caller;

  for my $name ( @names ) {
    my $fullname;
    my $sr = *{ qualify_to_ref($name,$calling_package) }{CODE};
    if ( defined $sr ) { 
      $fullname = qualify($name,$calling_package);
    }
    else {
      warn "Can't find subroutine named '$name'\n";
      next;
    }
    local $Hook::WrapSub::UNWRAP = 1;
    my $cr = $sr->();
    if ( defined $cr and $cr =~ /\bCODE\b/ ) {
      $^W = 0;
      no strict 'refs';
      *{ $fullname } = $cr;
    }
    else {
      warn "Subroutine '$fullname' not wrapped!";
    }
  }
}

1;

=head1 AUTHOR

jdporter@min.net (John Porter)

=head1 COPYRIGHT

This is free software.  This software may be modified and/or
distributed under the same terms as Perl itself.

=cut

