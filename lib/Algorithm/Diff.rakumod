class Algorithm::Diff {

# # McIlroy-Hunt diff algorithm
# # Adapted from the Smalltalk code of Mario I. Wolczko, <mario@wolczko.com>
# # by Ned Konz, perl@bike-nomad.com
# # Updates by Tye McQueen, http://perlmonks.org/?node=tye
#
# Raku port by Philip Mabon aka: takadonet.
# Additional porting by Stephen Schulze, aka: thundergnat.



# default key generator to use in the most common case:
# comparison of two strings

my &default_keyGen = { @_[0] }

# Create a hash that maps each element of @aCollection to the set of
# positions it occupies in @aCollection, restricted to the elements
# within the range of indexes specified by $start and $end.
# The fourth parameter is a subroutine reference that will be called to
# generate a string to use as a key.
#
# my %hash = _withPositionsOfInInterval( @array, $start, $end, &keyGen );

sub _withPositionsOfInInterval( @aCollection, $start, $end, &keyGen ) {
    my %d;
    for $start .. $end -> $index {
        %d{keyGen(@aCollection[$index])}.unshift($index);
    }
    %d
}

# Find the place at which aValue would normally be inserted into the
# array. If that place is already occupied by aValue, do nothing, and
# return undef. If the place does not exist (i.e., it is off the end of
# the array), add it to the end, otherwise replace the element at that
# point with aValue.  It is assumed that the array's values are numeric.
# This is where the bulk (75%) of the time is spent in this module, so
# try to make it fast!

our sub _replaceNextLargerWith( @array, $aValue, $high is copy ) {
    $high ||= +@array-1;

    # off the end?
    if  $high == -1 || $aValue > @array[*-1] {
        @array.push($aValue);
        return $high + 1;
    }

    # binary search for insertion point...
    my $low = 0;
    my $index;
    my $found;
    while $low <= $high {
        $index = (( $high + $low ) / 2).Int;
        $found = @array[$index];

        if $aValue == $found {
            return Int;
        }
        elsif  $aValue > $found {
            $low = $index + 1;
        }
        else {
            $high = $index - 1;
        }
    }

    # now insertion point is in $low.
    @array[$low] = $aValue;    # overwrite next larger
    $low
}

# This method computes the longest common subsequence in @a and @b.

# Result is array whose contents is such that
#   @a[ $i ] == @b[ @result[ $i ] ]
# foreach $i in ( 0 .. ^@result ) if @result[ $i ] is defined.

# An additional argument may be passed; this is a hash or key generating
# function that should return a string that uniquely identifies the given
# element.  It should be the case that if the key is the same, the elements
# will compare the same. If this parameter is undef or missing, the key
# will be the element as a string.

# By default, comparisons will use "eq" and elements will be turned into keys
# using the default stringizing operator '""'.

# If passed two arrays, trim any leading or trailing common elements, then
# process (&prepare) the second array to a hash and redispatch
our proto sub _longestCommonSubsequence(@a,$,$counting?,&fcn?,%args?,*%) {*}

our multi sub _longestCommonSubsequence(
    @a,
    @b,
    $counting = 0,
    &keyGen = &default_keyGen
) {
    my sub compare( $a, $b ) { keyGen( $a ) eq keyGen( $b ) }

    my ( $aStart, $aFinish ) = ( 0, +@a-1 );
    my ( $bStart, $bFinish ) = ( 0, +@b-1 );
    my @matchVector;
    my ( $prunedCount, %bMatches ) = ( 0, %({}) );

    # First we prune off any common elements at the beginning
    while  $aStart <= $aFinish
        and $bStart <= $bFinish
        and compare( @a[$aStart], @b[$bStart]) {
            @matchVector[ $aStart++ ] = $bStart++;
            $prunedCount++;
    }

    # now the end
    while  $aStart <= $aFinish
        and $bStart <= $bFinish
        and compare( @a[$aFinish], @b[$bFinish] ) {
            @matchVector[ $aFinish-- ] = $bFinish--;
            $prunedCount++;
    }

    # Now compute the equivalence classes of positions of elements
    %bMatches = _withPositionsOfInInterval( @b, $bStart, $bFinish, &keyGen);

    # and redispatch
    _longestCommonSubsequence(
        @a,
        %bMatches,
        $counting,
        &keyGen,
        PRUNED   => $prunedCount,
        ASTART   => $aStart,
        AFINISH  => $aFinish,
        MATCHVEC => @matchVector
    )
}

our multi sub _longestCommonSubsequence(
    @a,
    %bMatches,
    $counting = 0,
    &keyGen = &default_keyGen,
    :PRUNED( $prunedCount ),
    :ASTART( $aStart ) = 0,
    :AFINISH( $aFinish ) = +@a-1,
    :MATCHVEC( @matchVector ) = []
) {
    my ( @thresh, @links, $ai );
    for $aStart .. $aFinish -> $i {
         $ai = keyGen( @a[$i] );

         if %bMatches{$ai}:exists {
             my $k;
             for @(%bMatches{$ai}) -> $j {
                 # optimization: most of the time this will be true
                 if ( $k and @thresh[$k] > $j and @thresh[ $k - 1 ] < $j ) {
                      @thresh[$k] = $j;
                 }
                 else {
                      $k = _replaceNextLargerWith( @thresh, $j, $k );
                 }

                 # oddly, it's faster to always test this (CPU cache?).
                 # ( still true for Raku? need to test. )
                 if $k.defined {
                      @links[$k] = $k
                        ?? [  @links[ $k - 1 ] , $i, $j ]
                        !! [  Mu, $i, $j ];
                 }
            }
        }
    }
    if @thresh {
        return $prunedCount + @thresh if $counting;
        loop ( my $link = @links[+@thresh-1] ; $link ; $link = $link[0] ) {
             @matchVector[ $link[1] ] = $link[2];
        }
    }
    elsif $counting {
        return $prunedCount;
    }
    @matchVector
}

sub traverse_sequences(
    @a,
    @b,
    &keyGen = &default_keyGen,
    :MATCH( &match ),
    :DISCARD_A( &discard_a ),
    :DISCARD_B( &discard_b ),
    :A_FINISHED( &finished_a ) is copy,
    :B_FINISHED( &finished_b ) is copy
) is export(:traverse_sequences :DEFAULT) {

    my @matchVector = _longestCommonSubsequence( @a, @b, 0, &keyGen );

   # Process all the lines in @matchVector
    my ( $lastA, $lastB, $bi ) = ( +@a-1, +@b-1, 0 );
    my $ai;

    loop ( $ai = 0 ; $ai < +@matchVector ; $ai++ ) {
        my $bLine = @matchVector[$ai];
        if $bLine.defined {    # matched
             discard_b( $ai, $bi++ ) while $bi < $bLine;
             match( $ai, $bi++ );
        }
        else {
             discard_a( $ai, $bi);
        }
    }

    # The last entry (if any) processed was a match.
    # $ai and $bi point just past the last matching lines in their sequences.

    while  $ai <= $lastA or $bi <= $lastB {
        # last A?
        if  $ai == $lastA + 1 and $bi <= $lastB {
            if &finished_a.defined {
                finished_a( $lastA );
                &finished_a = sub {};
            }
            else {
                discard_b( $ai, $bi++ ) while $bi <= $lastB;
            }
        }

        # last B?
        if ( $bi == $lastB + 1 and $ai <= $lastA ) {
            if &finished_b.defined {
                finished_b( $lastB );
                &finished_b = sub {};
            }
            else {
                discard_a( $ai++, $bi ) while $ai <= $lastA;
            }
        }

        discard_a( $ai++, $bi ) if $ai <= $lastA;
        discard_b( $ai, $bi++ ) if $bi <= $lastB;
    }

    1
}

sub traverse_balanced(
    @a,
    @b,
    &keyGen = &default_keyGen,
    :MATCH( &match ),
    :DISCARD_A( &discard_a ),
    :DISCARD_B( &discard_b ),
    :CHANGE( &change )
) is export {
    my @matchVector = _longestCommonSubsequence( @a, @b, 0, &keyGen );
    # Process all the lines in match vector
    my ( $lastA, $lastB ) = ( +@a-1, +@b-1);
    my ( $bi, $ai, $ma )  = ( 0, 0, -1 );
    my $mb;

    loop {
        # Find next match indices $ma and $mb
        repeat {
            $ma++;
        } while
                $ma < +@matchVector
            &&  !(@matchVector[$ma].defined);

        last if $ma >= +@matchVector;    # end of matchVector?
        $mb = @matchVector[$ma];

        # Proceed with discard a/b or change events until
        # next match
        while  $ai < $ma || $bi < $mb {

            if  $ai < $ma && $bi < $mb {

                # Change
                if &change.defined {
                    change( $ai++, $bi++);
                }
                else {
                    discard_a( $ai++, $bi);
                    discard_b( $ai, $bi++);
                }
            }
            elsif $ai < $ma {
                discard_a( $ai++, $bi);
            }
            else {
                # $bi < $mb
                discard_b( $ai, $bi++);
            }
        }

        # Match
        match( $ai++, $bi++ );
    }

    while  $ai <= $lastA || $bi <= $lastB {
        if  $ai <= $lastA && $bi <= $lastB {
            # Change
            if &change.defined {
                 change( $ai++, $bi++);
            }
            else {
                discard_a( $ai++, $bi);
                discard_b( $ai, $bi++);
            }
        }
        elsif  $ai <= $lastA {
            discard_a( $ai++, $bi);
        }
        else {
            # $bi <= $lastB
            discard_b( $ai, $bi++);
        }
    }

    1
}

sub prepare ( @a, &keyGen = &default_keyGen ) is export {
    _withPositionsOfInInterval( @a, 0, +@a-1, &keyGen )
}

proto sub LCS(|) is export {*}
multi sub LCS( %b, @a, &keyGen = &default_keyGen ) {
   # rearrange args and re-dispatch
   LCS( @a, %b, &keyGen )
}

multi sub LCS( @a, @b, &keyGen = &default_keyGen ) {
    my @matchVector = _longestCommonSubsequence( @a, @b, 0, &keyGen);
    @a[(^@matchVector).grep: { @matchVector[$^a].defined }]
}


multi sub LCS( @a, %b, &keyGen = &default_keyGen ) {
    my @matchVector = _longestCommonSubsequence( @a, %b, 0, &keyGen);
    @a[(^@matchVector).grep: { @matchVector[$^a].defined }];
}

sub LCS_length( @a, @b, &keyGen = &default_keyGen ) is export {
    _longestCommonSubsequence( @a, @b, 1, &keyGen )
}


sub LCSidx( @a, @b, &keyGen = &default_keyGen ) is export {
     my @match = _longestCommonSubsequence( @a, @b, 0, &keyGen );
     my $amatch_indices = (^@match).grep({ @match[$^a].defined }).list;
     my $bmatch_indices = @match[@$amatch_indices];
     ($amatch_indices, $bmatch_indices);
}

sub compact_diff( @a, @b, &keyGen = &default_keyGen ) is export {
     my ( $am, $bm ) = LCSidx( @a, @b, &keyGen );
     my @am = $am.list;
     my @bm = $bm.list;
     my @cdiff;
     my ( $ai, $bi ) = ( 0, 0 );
     @cdiff.append: $ai, $bi;
     loop {
         while @am && $ai == @am.[0] && $bi == @bm.[0] {
             @am.shift;
             @bm.shift;
             ++$ai, ++$bi;
         }
         @cdiff.append: $ai, $bi;
         last if !@am;
         $ai = @am.[0];
         $bi = @bm.[0];
         @cdiff.append: $ai, $bi;
     }
     @cdiff.append( +@a, +@b )
         if  $ai < @a || $bi < @b;
     @cdiff
}

sub diff( @a, @b ) is export {
    my ( @retval, @hunk );
    traverse_sequences(
      @a, @b,
      MATCH     => sub ($x,$y) { @retval.append( @hunk ); @hunk = ()   },
      DISCARD_A => sub ($x,$y) { @hunk.push( [ '-', $x, @a[ $x ] ] ) },
      DISCARD_B => sub ($x,$y) { @hunk.push( [ '+', $y, @b[ $y ] ] ) }
    );
    @retval, @hunk
}

sub sdiff( @a, @b ) is export {
    my @retval;
    traverse_balanced(
      @a, @b,
      MATCH     => sub ($x,$y) { @retval.push( [ 'u', @a[ $x ], @b[ $y ] ] ) },
      DISCARD_A => sub ($x,$y) { @retval.push( [ '-', @a[ $x ],    ''    ] ) },
      DISCARD_B => sub ($x,$y) { @retval.push( [ '+',    ''   , @b[ $y ] ] ) },
      CHANGE    => sub ($x,$y) { @retval.push( [ 'c', @a[ $x ], @b[ $y ] ] ) }
    );
    @retval
}

#############################################################################
# Object Interface
#

has @._Idx  is rw; # Array of hunk indices
has @._Seq  is rw; # First , Second sequence
has $._End  is rw; # Diff between forward and reverse pos
has $._Same is rw; # 1 if pos 1 contains unchanged items
has $._Base is rw; # Added to range's min and max
has $._Pos  is rw; # Which hunk is currently selected
has $._Off  is rw; # Offset into _Idx for current position
has $._Min = -2;   # Added to _Off to get min instead of max+1

method new ( @seq1, @seq2, &keyGen = &default_keyGen ) {
    my @cdif = compact_diff( @seq1, @seq2, &keyGen );
    my $same = 1;
    if 0 == @cdif[2]  &&  0 == @cdif[3] {
        $same = 0;
        @cdif.splice( 0, 2 );
    }

    Algorithm::Diff.bless(
        :_Idx( @cdif ),
        :_Seq( '', [@seq1], [@seq2] ),
        :_End( ((1 + @cdif ) / 2).Int ),
        :_Same( $same ),
        :_Base( 0 ),
        :_Pos( 0 ),
        :_Off( 0 ),
    )
}

# sanity check to make sure Pos index is a defined & non-zero.
method _ChkPos {
   die( "Method illegal on a \"Reset\" Diff object" )
     unless $._Pos;
}

# increment Pos index pointer; default: +1, or passed parameter.
method Next ($steps? is copy ) {
    $steps = 1 if !$steps.defined;
    if $steps {
        my $pos = $._Pos;
        my $new = $pos + $steps;
        $new = 0 if ($pos and $new) < 0;
        self.Reset( $new );
    }
    $._Pos
}

# inverse of Next.
method Prev ( $steps? is copy ) {
    $steps  = 1 unless $steps.defined;
    my $pos = self.Next( -$steps );
    $pos -= $._End if $pos;
    $pos
}

# set the Pos pointer to passed index or 0 if none passed.
method Reset ( $pos? is copy ) {
    $pos = 0 unless $pos.defined;
    $pos += $._End if $pos < 0;
    $pos = 0 if $pos < 0 || $._End <= $pos;
    $._Pos = $pos // 0;
    $._Off = 2 * $pos - 1;
    self
}

# make sure a valid hunk is at the sequence/offset.
method _ChkSeq ( $seq ) {
    1 == $seq  || 2 == $seq
      ?? $seq + $._Off
      !! die( "Invalid sequence number ($seq); must be 1 or 2" );
}

# Change indexing base to the passed parameter (0 or 1 typically).
method Base ( $base? ) {
    my $oldBase = $._Base;
    $._Base = 0 + $base if $base.defined;
    $oldBase
}

# Generate a new Diff object bassed on an existing one.
method Copy ( $pos?, $base? ) {
    my $you = self.clone;
    $you.Reset( $pos ) if $pos.defined;
    $you.Base( $base );
    $you
}

# returns the index of the first item in a given hunk.
method Min ( $seq, $base? is copy ) {
    self._ChkPos;
    my $off = self._ChkSeq( $seq );
    $base = $._Base if !$base.defined;
    $base + @._Idx[ $off + $._Min ]
}

# returns the index of the last item in a given hunk.
method Max ( $seq, $base? is copy ) {
    self._ChkPos;
    my $off = self._ChkSeq( $seq );
    $base = $._Base if !$base.defined;
    $base + @._Idx[ $off ] - 1
}

# returns the indicies of the items in a given hunk.
method Range ( $seq, $base? is copy ) {
    self._ChkPos;
    my $off = self._ChkSeq( $seq );
    $base = $._Base if !$base.defined;
    ( $base + @._Idx[ $off + $._Min ] )
     .. ( $base + @._Idx[ $off ] - 1 )
}

# returns the items in a given hunk.
method Items ( $seq ) {
    self._ChkPos;
    my $off = self._ChkSeq( $seq );
    @._Seq[$seq][@._Idx[ $off + $._Min ] ..  @._Idx[ $off ] - 1 ]
}

# returns a bit mask representing the operations to change the current
# hunk from seq2 to seq1.
# 0 - no change
# 1 - delete items from sequence 1
# 2 - insert items from sequence 2
# 3 - replace items from sequence 1 with those from sequence 2
method Diff {
    self._ChkPos;
    return 0 if $._Same == ( 1 +& $._Pos );
    my $ret = 0;
    my $off = $._Off;
    for 1, 2 -> $seq {
        $ret +|= $seq
            if  @._Idx[ $off + $seq + $._Min ]
            <   @._Idx[ $off + $seq ];
    }
    $ret
}

# returns the items in the current hunk if they are equivalent
# or an empty list if not.
method Same {
     self._ChkPos;
     $._Same != ( 1 +& $._Pos )
       ?? ()
       !! self.Items(1)
}

} # end Algorithm::Diff

# ############################################################################
# Unported perl 5 object methods. Everything below except Die is to support Get
# with its extensive symbol table mangling. It's not worth the aggravation.


# sub Die
# {
#     require Carp;
#     Carp::confess( @_ );
# }

# sub getObjPkg
# {
#     my( $us )= @_;
#     return ref $us   if  ref $us;
#     return $us . "::_obj";
# }

# my %getName;
# BEGIN {
#     %getName= (
#         same => \&Same,
#         diff => \&Diff,
#         base => \&Base,
#         min  => \&Min,
#         max  => \&Max,
#         range=> \&Range,
#         items=> \&Items, # same thing
#     );
# }

# sub Get
# {
#     my $me= shift @_;
#     $me->_ChkPos();
#     my @value;
#     for my $arg (  @_  ) {
#         for my $word (  split ' ', $arg  ) {
#             my $meth;
#             if(     $word !~ /^(-?\d+)?([a-zA-Z]+)([12])?$/
#                 ||  not  $meth= $getName{ lc $2 }
#             ) {
#                 Die( $Root, ", Get: Invalid request ($word)" );
#             }
#             my( $base, $name, $seq )= ( $1, $2, $3 );
#             push @value, scalar(
#                 4 == length($name)
#                     ? $meth->( $me )
#                     : $meth->( $me, $seq, $base )
#             );
#         }
#     }
#     if(  wantarray  ) {
#         return @value;
#     } elsif(  1 == @value  ) {
#         return $value[0];
#     }
#     Die( 0+@value, " values requested from ",
#         $Root, "'s Get in scalar context" );
# }


# my $Obj= getObjPkg($Root);
# no strict 'refs';

# for my $meth (  qw( new getObjPkg )  ) {
#     *{$Root."::".$meth} = \&{$meth};
#     *{$Obj ."::".$meth} = \&{$meth};
# }
# for my $meth (  qw(
#     Next Prev Reset Copy Base Diff
#     Same Items Range Min Max Get
#     _ChkPos _ChkSeq
# )  ) {
#     *{$Obj."::".$meth} = \&{$meth};
# }
#############################################################

=begin pod

=head1 NAME

Algorithm::Diff - Compute `intelligent' differences between two files / lists

=head1 SYNOPSIS

=begin code :lang<raku>

use Algorithm::Diff;

# This example produces traditional 'diff' output:

my $diff = Algorithm::Diff.new( @seq1, @seq2 );

$diff.Base( 1 );   # Return line numbers, not indices
while $diff.Next {
    next   if  $diff.Same;
    my $sep = '';
    if !$diff.Items(2) {
        printf "%d,%dd%d\n",
            $diff.Min(1), $diff.Max(1), $diff.Max(2);
    }
    elsif !$diff.Items(1) {
        printf "%da%d,%d\n",
            $diff.Min(1), $diff.Max(1), $diff.Max(2);
    }
    else {
        $sep = "---\n";
        printf "%d,%dc%d,%d\n",
            $diff.Min(1), $diff.Max(1), $diff.Min(2), $diff.Max(2);
    }
    print "< $_" for  $diff.Items(1);
    print $sep;
    print "> $_" for  $diff.Items(2);
}

# Alternate interfaces:

use Algorithm::Diff;

@lcs   = LCS( @seq1, @seq2 );
$count = LCS_length( @seq1, @seq2 );

( $seq1idxlist, $seq2idxlist ) = LCSidx( @seq1, @seq2 );


# Complicated interfaces:

@diffs  = diff( @seq1, @seq2 );

@sdiffs = sdiff( @seq1, @seq2 );

@cdiffs = compact_diff( @seq1, @seq2 );

traverse_sequences(
    @seq1,
    @seq2,
    MATCH     => &callback1,
    DISCARD_A => &callback2,
    DISCARD_B => &callback3,
    &key_generator,
);

traverse_balanced(
    @seq1,
    @seq2,
    MATCH     => &callback1,
    DISCARD_A => &callback2,
    DISCARD_B => &callback3,
    CHANGE    => &callback4,
    &key_generator,
);

=end code

=head1 INTRODUCTION

(by Mark-Jason Dominus)

I once read an article written by the authors of C<diff>; they said
that they worked very hard on the algorithm until they found the
right one.

I think what they ended up using (and I hope someone will correct me,
because I am not very confident about this) was the `longest common
subsequence' method.  In the LCS problem, you have two sequences of
items:

    a b c d f g h j q z

    a b c d e f g i j k r x y z

and you want to find the longest sequence of items that is present in
both original sequences in the same order.  That is, you want to find
a new sequence I<S> which can be obtained from the first sequence by
deleting some items, and from the secend sequence by deleting other
items.  You also want I<S> to be as long as possible.  In this case I<S>
is

    a b c d f g j z

From there it's only a small step to get diff-like output:

    e   h i   k   q r x y
    +   - +   +   - + + +

This module solves the LCS problem.  It also includes a canned function
to generate C<diff>-like output.

It might seem from the example above that the LCS of two sequences is
always pretty obvious, but that's not always the case, especially when
the two sequences have many repeated elements.  For example, consider

    a x b y c z p d q
    a b c a x b y c z

A naive approach might start by matching up the C<a> and C<b> that
appear at the beginning of each sequence, like this:

    a x b y c         z p d q
    a   b   c a b y c z

This finds the common subsequence C<a b c z>.  But actually, the LCS
is C<a x b y c z>:

          a x b y c z p d q
    a b c a x b y c z

or

    a       x b y c z p d q
    a b c a x b y c z

=head1 USAGE

(See also the README file and several example
scripts include with this module.)

This module now provides an object-oriented interface that uses less
memory and is easier to use than most of the previous procedural
interfaces.  It also still provides several exportable functions.  We'll
deal with these in ascending order of difficulty:  C<LCS>,
C<LCS_length>, C<LCSidx>, OO interface, C<prepare>, C<diff>, C<sdiff>,
C<traverse_sequences>, and C<traverse_balanced>.

=head2 LCS

Given two lists of items, LCS returns an array containing
their longest common subsequence.

=begin code :lang<raku>

@lcs = LCS( @seq1, @seq2 );

=end code

C<LCS> may be passed an optional third parameter; this is a CODE
reference to a key generation function.  See L</KEY GENERATION
FUNCTIONS>.

=begin code :lang<raku>

@lcs = LCS( @seq1, @seq2, $keyGen );

=end code

=head2 LCS_length

This is just like C<LCS> except it only returns the length of the
longest common subsequence.  This provides a performance gain of about
9% compared to C<LCS>.

=head2 LCSidx

Like C<LCS> except it returns references to two lists.  The first list
contains the indices into @seq1 where the LCS items are located.  The
second list contains the indices into @seq2 where the LCS items are located.

Therefore, the following three lists will contain the same values:

=begin code :lang<raku>

my( $idx1, $idx2 ) = LCSidx( @seq1, @seq2 );
my @list1 = @seq1[ $idx1 ];
my @list2 = @seq2[ $idx2 ];
my @list3 = LCS( @seq1, @seq2 );

=end code

=head2 new

=begin code :lang<raku>

$diff = Algorithm::Diffs.new( @seq1, @seq2 );
$diff = Algorithm::Diffs.new( @seq1, @seq2, &keyGen );

=end code

C<new> computes the smallest set of additions and deletions necessary
to turn the first sequence into the second and compactly records them
in the object.

You use the object to iterate over I<hunks>, where each hunk represents
a contiguous section of items which should be added, deleted, replaced,
or left unchanged.

The following summary of all of the methods looks a lot like Perl code
but some of the symbols have different meanings:

    [ ]     Encloses optional arguments
    :       Is followed by the default value for an optional argument
    |       Separates alternate return results

Method summary:

=begin code :lang<raku>

$obj        = Algorithm::Diff.new( @seq1, @seq2, [ &keyGen ] );
$pos        = $obj.Next(  [ $count : 1 ] );
$revPos     = $obj.Prev(  [ $count : 1 ] );
$obj        = $obj.Reset( [ $pos : 0 ] );
$copy       = $obj.Copy(  [ $pos, [ $newBase ] ] );
$oldBase    = $obj.Base(  [ $newBase ] );

=end code

Note that all of the following methods C<die> if used on an object that
is "reset" (not currently pointing at any hunk).

=begin code :lang<raku>

$bits    = $obj.Diff;
@items   = $obj.Same;
@items   = $obj.Items( $seqNum );
@idxs    = $obj.Range( $seqNum, [ $base ] );
$minIdx  = $obj.Min(   $seqNum, [ $base ] );
$maxIdx  = $obj.Max(   $seqNum, [ $base ] );
@values  = $obj.Get(   @names );

=end code

Passing in an undefined value for an optional argument is always treated the
same as if no argument were passed in.

=item Next

=begin code :lang<raku>

$pos = $diff.Next;      # Move forward 1 hunk
$pos = $diff.Next( 2 ); # Move forward 2 hunks
$pos = $diff.Next(-5);  # Move backward 5 hunks

=end code

C<Next> moves the object to point at the next hunk.  The object starts
out "reset", which means it isn't pointing at any hunk.  If the object
is reset, then C<Next()> moves to the first hunk.

C<Next> returns a true value iff the move didn't go past the last hunk.
So C<Next(0)> will return true iff the object is not reset.

Actually, C<Next> returns the object's new position, which is a number
between 1 and the number of hunks (inclusive), or returns a false value.

=item Prev

C<Prev($N)> is almost identical to C<Next(-$N)>; it moves to the $Nth
previous hunk.  On a 'reset' object, C<Prev()> [and C<Next(-1)>] move
to the last hunk.

The position returned by C<Prev> is relative to the I<end> of the
hunks; -1 for the last hunk, -2 for the second-to-last, etc.

=item C<Reset>

=begin code :lang<raku>

$diff.Reset;       # Reset the object's position
$diff.Reset($pos); # Move to the specified hunk
$diff.Reset(1);    # Move to the first hunk
$diff.Reset(-1);   # Move to the last hunk

=end code

C<Reset> returns the object, so, for example, you could use
C<< $diff.Reset().Next(-1) >> to get the number of hunks.

=item Copy

=begin code :lang<raku>

$copy = $diff.Copy( $newPos, $newBase );

=end code

C<Copy> returns a copy of the object.  The copy and the orignal object
share most of their data, so making copies takes very little memory.
The copy maintains its own position (separate from the original), which
is the main purpose of copies.  It also maintains its own base.

By default, the copy's position starts out the same as the original
object's position.  But C<Copy> takes an optional first argument to set the
new position, so the following three snippets are equivalent:

=begin code :lang<raku>

$copy = $diff.Copy($pos);

$copy = $diff.Copy;
$copy.Reset($pos);

$copy = $diff.Copy.Reset($pos);

=end code

C<Copy> takes an optional second argument to set the base for
the copy.  If you wish to change the base of the copy but leave
the position the same as in the original, here are two
equivalent ways:

=begin code :lang<raku>

$copy = $diff.Copy;
$copy.Base( 0 );

$copy = $diff.Copy(Nil,0);

=end code

Here are two equivalent way to get a "reset" copy:

=begin code :lang<raku>

$copy = $diff.Copy(0);

$copy = $diff.Copy.Reset;

=end code

=item Diff

=begin code :lang<raku>

$bits = $obj.Diff;

=end code

C<Diff> returns a true value iff the current hunk contains items that are
different between the two sequences.  It actually returns one of the
follow 4 values:

=item 3

C<3==(1|2)>.  This hunk contains items from @seq1 and the items
from @seq2 that should replace them.  Both sequence 1 and 2
contain changed items so both the 1 and 2 bits are set.

=item 2

This hunk only contains items from @seq2 that should be inserted (not
items from @seq1).  Only sequence 2 contains changed items so only the 2
bit is set.

=item 1

This hunk only contains items from @seq1 that should be deleted (not
items from @seq2).  Only sequence 1 contains changed items so only the 1
bit is set.

=item 0

This means that the items in this hunk are the same in both sequences.
Neither sequence 1 nor 2 contain changed items so neither the 1 nor the
2 bits are set.

=item Same

C<Same> returns a true value iff the current hunk contains items that
are the same in both sequences.  It actually returns the list of items
if they are the same or an emty list if they aren't.  In a scalar
context, it returns the size of the list.

=item Items

=begin code :lang<raku>

$count = $diff.Items(2);
@items = $diff.Items($seqNum);

=end code

C<Items> returns the (number of) items from the specified sequence that
are part of the current hunk.

If the current hunk contains only insertions, then
C<< $diff.Items(1) >> will return an empty list (0 in a scalar conext).
If the current hunk contains only deletions, then C<< $diff.Items(2) >>
will return an empty list (0 in a scalar conext).

If the hunk contains replacements, then both C<< $diff.Items(1) >> and
C<< $diff.Items(2) >> will return different, non-empty lists.

Otherwise, the hunk contains identical items and all of the following
will return the same lists:

=begin code :lang<raku>

@items = $diff.Items(1);
@items = $diff.Items(2);
@items = $diff.Same;

=end code

=item Range

=begin code :lang<raku>

$count = $diff.Range( $seqNum );
@indices = $diff.Range( $seqNum );
@indices = $diff.Range( $seqNum, $base );

=end code

C<Range> is like C<Items> except that it returns a list of I<indices> to
the items rather than the items themselves.  By default, the index of
the first item (in each sequence) is 0 but this can be changed by
calling the C<Base> method.  So, by default, the following two snippets
return the same lists:

=begin code :lang<raku>

@list = $diff.Items(2);
@list = @seq2[ $diff.Range(2) ];

=end code

You can also specify the base to use as the second argument.  So the
following two snippets I<always> return the same lists:

=begin code :lang<raku>

@list = $diff.Items(1);
@list = @seq1[ $diff.Range(1,0) ];

=end code

=item Base

=begin code :lang<raku>

$curBase = $diff.Base();
$oldBase = $diff.Base($newBase);

=end code

C<Base> sets and/or returns the current base (usually 0 or 1) that is
used when you request range information.  The base defaults to 0 so
that range information is returned as array indices.  You can set the
base to 1 if you want to report traditional line numbers instead.

=item Min

=begin code :lang<raku>

$min1 = $diff.Min(1);
$min = $diff.Min( $seqNum, $base );

=end code

C<Min> returns the first value that C<Range> would return (given the
same arguments) or returns C<undef> if C<Range> would return an empty
list.

=item Max

C<Max> returns the last value that C<Range> would return or C<Nil>.

=head2 prepare

Given a reference to a list of items, C<prepare> returns a reference
to a hash which can be used when comparing this sequence to other
sequences with C<LCS> or C<LCS_length>.

=begin code :lang<raku>

$prep = prepare( @seq1 );
for ^10_000 {
    @lcs = LCS( $prep, @seq2[$_] );
    # do something useful with @lcs
}

=end code

C<prepare> may be passed an optional third parameter; this is a CODE
reference to a key generation function.  See L</KEY GENERATION
FUNCTIONS>.

=begin code :lang<raku>

$prep = prepare( @seq1, &keyGen );
for ^10_000 {
    @lcs = LCS( @seq2[$_], $prep, &keyGen );
    # do something useful with @lcs
}

=end code

Using C<prepare> provides a performance gain of about 50% when calling LCS
many times compared with not preparing.

=head2 diff

=begin code :lang<raku>

@diffs = diff( @seq1, @seq2 );

=end code

C<diff> computes the smallest set of additions and deletions necessary
to turn the first sequence into the second, and returns a description
of these changes.  The description is a list of I<hunks>; each hunk
represents a contiguous section of items which should be added,
deleted, or replaced.  (Hunks containing unchanged items are not
included.)

The return value of C<diff> is a list of hunks, or, in scalar context, a
reference to such a list.  If there are no differences, the list will be
empty.

Here is an example.  Calling C<diff> for the following two sequences:

    a b c e h j l m n p
    b c d e f j k l m r s t

would produce the following list:

=begin code :lang<raku>

(
  [ [ '-', 0, 'a' ] ],

  [ [ '+', 2, 'd' ] ],

  [ [ '-', 4, 'h' ],
    [ '+', 4, 'f' ] ],

  [ [ '+', 6, 'k' ] ],

  [ [ '-',  8, 'n' ],
    [ '-',  9, 'p' ],
    [ '+',  9, 'r' ],
    [ '+', 10, 's' ],
    [ '+', 11, 't' ] ],
)

=end code

There are five hunks here.  The first hunk says that the C<a> at
position 0 of the first sequence should be deleted (C<->).  The second
hunk says that the C<d> at position 2 of the second sequence should
be inserted (C<+>).  The third hunk says that the C<h> at position 4
of the first sequence should be removed and replaced with the C<f>
from position 4 of the second sequence.  And so on.

C<diff> may be passed an optional third parameter; this is a CODE
reference to a key generation function.  See L</KEY GENERATION
FUNCTIONS>.

# Additional parameters, if any, will be passed to the key generation
# routine.

=head2 sdiff

=begin code :lang<raku>

@sdiffs = sdiff( @seq1, @seq2 );

=end code

C<sdiff> computes all necessary components to show two sequences
and their minimized differences side by side, just like the
Unix-utility I<sdiff> does:

    same             same
    before     |     after
    old        <     -
    -          >     new

It returns a list of array refs, each pointing to an array of display
instructions. If there are no differences, the list will have one entry per
item, each indicating that the item was unchanged.

Display instructions consist of three elements: A modifier indicator
(C<+>: Element added, C<->: Element removed, C<u>: Element unmodified,
C<c>: Element changed) and the value of the old and new elements, to
be displayed side-by-side.

An C<sdiff> of the following two sequences:

    a b c e h j l m n p
    b c d e f j k l m r s t

results in

=begin code :lang<raku>

( [ '-', 'a', ''  ],
  [ 'u', 'b', 'b' ],
  [ 'u', 'c', 'c' ],
  [ '+', '',  'd' ],
  [ 'u', 'e', 'e' ],
  [ 'c', 'h', 'f' ],
  [ 'u', 'j', 'j' ],
  [ '+', '',  'k' ],
  [ 'u', 'l', 'l' ],
  [ 'u', 'm', 'm' ],
  [ 'c', 'n', 'r' ],
  [ 'c', 'p', 's' ],
  [ '+', '',  't' ],
)

=end code

C<sdiff> may be passed an optional third parameter; this is a CODE
reference to a key generation function.  See L</KEY GENERATION
FUNCTIONS>.

# Additional parameters, if any, will be passed to the key generation
# routine.

=head2 compact_diff

C<compact_diff> is much like C<sdiff> except it returns a much more
compact description consisting of just one flat list of indices.  An
example helps explain the format:

=begin code :lang<raku>

my @a = <a b c   e  h j   l m n p     >;
my @b = <  b c d e f  j k l m    r s t>;
@cdiff = compact_diff( @a, @b );
# Returns:
#   @a      @b       @a       @b
#  start   start   values   values
(    0,      0,   #       =
     0,      0,   #    a  !
     1,      0,   #  b c  =  b c
     3,      2,   #       !  d
     3,      3,   #    e  =  e
     4,      4,   #    f  !  h
     5,      5,   #    j  =  j
     6,      6,   #       !  k
     6,      7,   #  l m  =  l m
     8,      9,   #  n p  !  r s t
    10,     12,   #
);

=end code

The 0th, 2nd, 4th, etc. entries are all indices into @seq1 (@a in the
above example) indicating where a hunk begins.  The 1st, 3rd, 5th, etc.
entries are all indices into @seq2 (@b in the above example) indicating
where the same hunk begins.

So each pair of indices (except the last pair) describes where a hunk
begins (in each sequence).  Since each hunk must end at the item just
before the item that starts the next hunk, the next pair of indices can
be used to determine where the hunk ends.

So, the first 4 entries (0..3) describe the first hunk.  Entries 0 and 1
describe where the first hunk begins (and so are always both 0).
Entries 2 and 3 describe where the next hunk begins, so subtracting 1
from each tells us where the first hunk ends.  That is, the first hunk
contains items C<$diff[0]> through C<$diff[2] - 1> of the first sequence
and contains items C<$diff[1]> through C<$diff[3] - 1> of the second
sequence.

In other words, the first hunk consists of the following two lists of items:

=begin code :lang<raku>

           #  1st pair     2nd pair
           # of indices   of indices
@list1 = @a[ $cdiff[0] .. $cdiff[2]-1 ];
@list2 = @b[ $cdiff[1] .. $cdiff[3]-1 ];
           # Hunk start   Hunk end

=end code

Note that the hunks will always alternate between those that are part of
the LCS (those that contain unchanged items) and those that contain
changes.  This means that all we need to be told is whether the first
hunk is a 'same' or 'diff' hunk and we can determine which of the other
hunks contain 'same' items or 'diff' items.

By convention, we always make the first hunk contain unchanged items.
So the 1st, 3rd, 5th, etc. hunks (all odd-numbered hunks if you start
counting from 1) all contain unchanged items.  And the 2nd, 4th, 6th,
etc. hunks (all even-numbered hunks if you start counting from 1) all
contain changed items.

Since @a and @b don't begin with the same value, the first hunk in our
example is empty (otherwise we'd violate the above convention).  Note
that the first 4 index values in our example are all zero.  Plug these
values into our previous code block and we get:

=begin code :lang<raku>

@hunk1a = @a[ 0 .. 0-1 ];
@hunk1b = @b[ 0 .. 0-1 ];

=end code

And C<0..-1> returns the empty list.

Move down one pair of indices (2..5) and we get the offset ranges for
the second hunk, which contains changed items.

Since C<@diff[2..5]> contains (0,0,1,0) in our example, the second hunk
consists of these two lists of items:

=begin code :lang<raku>

    @hunk2a = @a[ $cdiff[2] .. $cdiff[4]-1 ];
    @hunk2b = @b[ $cdiff[3] .. $cdiff[5]-1 ];
# or
    @hunk2a = @a[ 0 .. 1-1 ];
    @hunk2b = @b[ 0 .. 0-1 ];
# or
    @hunk2a = @a[ 0 .. 0 ];
    @hunk2b = @b[ 0 .. -1 ];
# or
    @hunk2a = ( 'a' );
    @hunk2b = ( );

=end code

That is, we would delete item 0 ('a') from @a.

Since C<@diff[4..7]> contains (1,0,3,2) in our example, the third hunk
consists of these two lists of items:

=begin code :lang<raku>

    @hunk3a = @a[ $cdiff[4] .. $cdiff[6]-1 ];
    @hunk3a = @b[ $cdiff[5] .. $cdiff[7]-1 ];
# or
    @hunk3a = @a[ 1 .. 3-1 ];
    @hunk3a = @b[ 0 .. 2-1 ];
# or
    @hunk3a = @a[ 1 .. 2 ];
    @hunk3a = @b[ 0 .. 1 ];
# or
    @hunk3a = qw( b c );
    @hunk3a = qw( b c );

=end code

Note that this third hunk contains unchanged items as our convention demands.

You can continue this process until you reach the last two indices,
which will always be the number of items in each sequence.  This is
required so that subtracting one from each will give you the indices to
the last items in each sequence.

=head2 traverse_sequences

C<traverse_sequences> used to be the most general facility provided by
this module (the new OO interface is more powerful and much easier to
use).

Imagine that there are two arrows.  Arrow A points to an element of
sequence A, and arrow B points to an element of the sequence B.
Initially, the arrows point to the first elements of the respective
sequences.  C<traverse_sequences> will advance the arrows through the
sequences one element at a time, calling an appropriate user-specified
callback function before each advance.  It willadvance the arrows in
such a way that if there are equal elements C<$A[$i]> and C<$B[$j]>
which are equal and which are part of the LCS, there will be some moment
during the execution of C<traverse_sequences> when arrow A is pointing
to C<$A[$i]> and arrow B is pointing to C<$B[$j]>.  When this happens,
C<traverse_sequences> will call the C<MATCH> callback function and then
it will advance both arrows.

Otherwise, one of the arrows is pointing to an element of its sequence
that is not part of the LCS.  C<traverse_sequences> will advance that
arrow and will call the C<DISCARD_A> or the C<DISCARD_B> callback,
depending on which arrow it advanced.  If both arrows point to elements
that are not part of the LCS, then C<traverse_sequences> will advance
one of them and call the appropriate callback, but it is not specified
which it will call.

The arguments to C<traverse_sequences> are the two sequences to
traverse, and a hash which specifies the callback functions, like this:

=begin code :lang<raku>

traverse_sequences(
    @seq1, @seq2,
    MATCH     => &callback_1,
    DISCARD_A => &callback_2,
    DISCARD_B => &callback_3,
);

=end code

Callbacks for MATCH, DISCARD_A, and DISCARD_B are invoked with at least
the indices of the two arrows as their arguments.  They are not expected
to return any values.  If a callback is omitted from the table, it is
not called.

Callbacks for A_FINISHED and B_FINISHED are invoked with at least the
corresponding index in A or B.

If arrow A reaches the end of its sequence, before arrow B does,
C<traverse_sequences> will call the C<A_FINISHED> callback when it
advances arrow B, if there is such a function; if not it will call
C<DISCARD_B> instead.  Similarly if arrow B finishes first.
C<traverse_sequences> returns when both arrows are at the ends of their
respective sequences.  It returns true on success and false on failure.
At present there is no way to fail.

C<traverse_sequences> may be passed an optional fourth parameter; this
is a CODE reference to a key generation function.  See L</KEY GENERATION
FUNCTIONS>.

C<traverse_sequences> does not have a useful return value; you are
expected to plug in the appropriate behavior with the callback
functions.

=head2 traverse_balanced

C<traverse_balanced> is an alternative to C<traverse_sequences>. It
uses a different algorithm to iterate through the entries in the
computed LCS. Instead of sticking to one side and showing element changes
as insertions and deletions only, it will jump back and forth between
the two sequences and report I<changes> occurring as deletions on one
side followed immediatly by an insertion on the other side.

In addition to the C<DISCARD_A>, C<DISCARD_B>, and C<MATCH> callbacks
supported by C<traverse_sequences>, C<traverse_balanced> supports
a C<CHANGE> callback indicating that one element got C<replaced> by another:

=begin code :lang<raku>

traverse_balanced(
    @seq1, @seq2,
    MATCH => $callback_1,
    DISCARD_A => $callback_2,
    DISCARD_B => $callback_3,
    CHANGE    => $callback_4,
);

=end code

If no C<CHANGE> callback is specified, C<traverse_balanced>
will map C<CHANGE> events to C<DISCARD_A> and C<DISCARD_B> actions,
therefore resulting in a similar behaviour as C<traverse_sequences>
with different order of events.

C<traverse_balanced> might be a bit slower than C<traverse_sequences>,
noticable only while processing huge amounts of data.

The C<sdiff> function of this module
is implemented as call to C<traverse_balanced>.

C<traverse_balanced> does not have a useful return value; you are expected to
plug in the appropriate behavior with the callback functions.

=head1 KEY GENERATION FUNCTIONS

Most of the functions accept an optional extra parameter.  This is a
CODE reference to a key generating (hashing) function that should return
a string that uniquely identifies a given element.  It should be the
case that if two elements are to be considered equal, their keys should
be the same (and the other way around).  If no key generation function
is provided, the key will be the element as a string.

By default, comparisons will use "eq" and elements will be turned into keys
using the default stringizing operator '""'.

Where this is important is when you're comparing something other than
strings.  If it is the case that you have multiple different objects
that should be considered to be equal, you should supply a key
generation function. Otherwise, you have to make sure that your arrays
contain unique references.

For instance, consider this example:

=begin code :lang<raku>

class Person {
    has $.name;
    has $.ssn;

    our sub hash($person) { $person.ssn }
}

my $person1 = Person.new( name => 'Joe', ssn => '123-45-6789' );
my $person2 = Person.new( name => 'Mary', ssn => '123-47-0000' );
my $person3 = Person.new( name => 'Pete', ssn => '999-45-2222' );
my $person4 = Person.new( name => 'Peggy', ssn => '123-45-9999' );
my $person5 = Person.new( name => 'Frank', ssn => '000-45-9999' );

=end code

If you did this:

=begin code :lang<raku>

my $array1 = [ $person1, $person2, $person4 ];
my $array2 = [ $person1, $person3, $person4, $person5 ];
Algorithm::Diff::diff( $array1, $array2 );

=end code

everything would work out OK (each of the objects would be converted
into a string like "Person<2832536624368>" for comparison).

But if you did this:

=begin code :lang<raku>

my $array1 = [ $person1, $person2, $person4 ];
my $array2 = [ $person1, $person3, $person4.clone, $person5 ];
Algorithm::Diff::diff( $array1, $array2 );

=end code

$person4 and $person4.clone (which have the same name and SSN)
would be seen as different objects. If you wanted them to be considered
equivalent, you would have to pass in a key generation function:

=begin code :lang<raku>

my $array1 = [ $person1, $person2, $person4 ];
my $array2 = [ $person1, $person3, $person4.clone, $person5 ];
Algorithm::Diff::diff( $array1, $array2, \&Person::hash );

=end code

This would use the 'ssn' field in each Person as a comparison key, and
so would consider $person4 and $person4.clone as equal.

=head1 AUTHOR

Based on Perl 5 version released by Tye McQueen
(http://perlmonks.org/?node=tye).

Initial procedural interface port by takadonet.
Further procedural porting and object interface port by Steve Schulze.

=head1 LICENSE

Parts Copyright (c) 2000-2004 Ned Konz.  All rights reserved.
Parts by Tye McQueen.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl.

=head1 CREDITS

Versions through 0.59 (and much of this documentation) were written by:

Mark-Jason Dominus, mjd-perl-diff@plover.com

This version borrows some documentation and routine names from
Mark-Jason's, but Diff.pm's code was completely replaced.

This code was adapted from the Smalltalk code of Mario Wolczko
<mario@wolczko.com>, which is available at
ftp://st.cs.uiuc.edu/pub/Smalltalk/MANCHESTER/manchester/4.0/diff.st

C<sdiff> and C<traverse_balanced> were written by Mike Schilli
<m@perlmeister.com>.

The algorithm is that described in
I<A Fast Algorithm for Computing Longest Common Subsequences>,
CACM, vol.20, no.5, pp.350-353, May 1977, with a few
minor improvements to improve the speed.

Much work was done by Ned Konz (perl@bike-nomad.com).

The OO interface and some other changes are by Tye McQueen.

Raku port by Philip Mabon (takadonet) and Steve Schulze (thundergnat)

Further maintenance by the Raku Community.

=head1 ORIGINAL README

This is a module for computing the difference between two files, two
strings, or any other two lists of things.  It uses an intelligent
algorithm similar to (or identical to) the one used by the Unix "diff"
program.  It is guaranteed to find the *smallest possible* set of
differences.

This package contains a few parts.

Algorithm::Diff is the module that contains several interfaces for which
computing the differences betwen two lists.

The several "diff" programs also included in this package use
Algorithm::Diff to find the differences and then they format the output.

Algorithm::Diff also includes some other useful functions such as "LCS",
which computes the longest common subsequence of two lists.

A::D is suitable for many uses.  You can use it for finding the smallest
set of differences between two strings, or for computing the most
efficient way to update the screen if you were replacing "curses".

Algorithm::DiffOld is a previous version of the module which is included
primarilly for those wanting to use a custom comparison function rather
than a key generating function (and who don't mind the significant
performance penalty of perhaps 20-fold).

diff.pl implements a "diff" in Perl that is as simple as (was
previously) possible so that you can see how it works.  The output
format is not compatible with regular "diff".  It needs to be
reimplemented using the OO interface to greatly simplify the code.

diffnew.pl implements a "diff" in Perl with full bells and whistles.  By
Mark-Jason, with code from cdiff.pl included.

cdiff.pl implements "diff" that generates real context diffs in either
traditional format or GNU unified format.  Original contextless
"context" diff supplied by Christian Murphy.  Modifications to make it
into a real full-featured diff with -c and -u options supplied by Amir
D. Karger.

Yes, you can use this program to generate patches.

OTHER RESOURCES

"Longest Common Subsequences", at
http://www.ics.uci.edu/~eppstein/161/960229.html

This code was adapted from the Smalltalk code of Mario Wolczko
<mario@wolczko.com>, which is available at
ftp://st.cs.uiuc.edu/pub/Smalltalk/MANCHESTER/manchester/4.0/diff.st

THANKS SECTION

Thanks to Ned Konz's for rewriting the module to greatly improve
performance, for maintaining it over the years, and for readilly handing
it over to me so I could plod along with my improvements.

(From Ned Konz's earlier versions):

Thanks to Mark-Jason Dominus for doing the original Perl version and
maintaining it over the last couple of years. Mark-Jason has been a huge
contributor to the Perl community and CPAN; it's because of people like
him that Perl has become a success.

Thanks to Mario Wolczko <mario@wolczko.com> for writing and making
publicly available his Smalltalk version of diff, which this Perl
version is heavily based on.

Thanks to Mike Schilli <m@perlmeister.com> for writing sdiff and
traverse_balanced and making them available for the Algorithm::Diff
distribution.

(From Mark-Jason Dominus' earlier versions):

Huge thanks to Amir Karger for adding full context diff support to
"cdiff.pl", and then for waiting patiently for five months while I let
it sit in a closet and didn't release it.  Thank you thank you thank
you, Amir!

Thanks to Christian Murphy for adding the first context diff format
support to "cdiff.pl".

=end pod
