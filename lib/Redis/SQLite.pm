
=head1 NAME

Redis::SQLite - Redis-Compatible module which writes to SQLite.

=cut

=head1 SYNOPSIS

=for example begin

    #!/usr/bin/perl -w

    use Redis::SQLite;
    use strict;

    my $db = Redis::SQLite->new();

    $db->set( "foo", "bar" );

    print $db->get( "foo" ) . "\n";

=for example end


=head1 DESCRIPTION

This package is an implementation of the L<Redis> Perl-client API, which
stores all data in an SQLite database rather than in RAM.

It is B<not> a drop-in replacement, because it doesn't implement all the
features you'd expect from the real Redis module.  Just enough to be useful.

=cut

=head1 COMPATIBILITY

This module is designed to be source compatible with the L<Redis> module,
providing you're only operating upon either sets or simple strings.
Specifically we do not support ZSET or HASH-related operations.

The following methods are implemented as part of the basic-functionality:

=over 8

=item APPEND

=item EXISTS

=item GET

=item GETSET

=item SET

=item TYPE

=item INCR

=item INCRBY

=item DECR

=item DECRBY

=item DEL

=item STRLEN

=back

The following set-related methods are implemented:

=over 8

=item SADD

=item SCARD

=item SDIFF

=item SDIFFSTORE

=item SINTER

=item SINTERSTORE

=item SISMEMBER

=item SMEMBERS

=item SMOVE

=item SPOP

=item SRANDMEMBER

=item SREM

=item SUNION

=item SUNIONSTORE

=back

The only missing set-method is C<SSCAN>, other methods which are missing
will raise a C<warn>ing.

=cut

=head1 METHODS

=cut


package Redis::SQLite;



use strict;
use warnings;
use DBI;


our $VERSION = '0.1';


=head2 new

Constructor.  The only (optional) argument is C<path> which will
change the default SQLite database-file location, if unspecified
C<~/.predis.db> will be used.

=cut

sub new
{
    my ( $proto, %supplied ) = (@_);
    my $class = ref($proto) || $proto;

    my $self = {};
    bless( $self, $class );

    # Create ~/.predis.db unless an alternative path was specified.
    my $home = $ENV{'HOME'} || (getpwuid($<))[7];
    my $file = $supplied{ 'path' } || "$home/.predis.db";

    my $create = 1;
    $create = 0 if ( -e $file );

    $self->{ 'db' } =
      DBI->connect( "dbi:SQLite:dbname=$file", "", "", { AutoCommit => 1 } );

    #
    #  Populate the database tables, if it was missing.
    #
    if ($create)
    {
        $self->{ 'db' }->do(
             "CREATE TABLE string (id INTEGER PRIMARY KEY, key UNIQUE, val );");
        $self->{ 'db' }
          ->do("CREATE TABLE sets (id INTEGER PRIMARY KEY, key, val );");
    }

    #
    #  This is potentially risky, but improves the throughput by several
    # orders of magnitude.
    #
    if ( !$ENV{ 'SAFE' } )
    {
        $self->{ 'db' }->do("PRAGMA synchronous = OFF");
        $self->{ 'db' }->do("PRAGMA journal_mode = MEMORY");
    }

    return $self;
}


=head2 append

Append the given string to the contents of the existing key, creating it
if didn't previously exist.

=cut

sub append
{
    my ( $self, $key, $data ) = (@_);

    my $r = $self->get($key);
    $r .= $data;
    $self->set( $key, $r );
}


=head2 exists

Does the given key exist?

=cut

sub exists
{
    my ( $self, $key ) = (@_);

    my $sql = $self->{ 'db' }->prepare("SELECT key FROM string WHERE key=?");
    $sql->execute($key);
    my $x = $sql->fetchrow_array() || undef;
    $sql->finish();

    if ($x)
    {
        return 1;
    }

    $sql = $self->{ 'db' }->prepare("SELECT key FROM sets WHERE key=?");
    $sql->execute($key);
    $x = $sql->fetchrow_array() || undef;
    $sql->finish();

    if ($x)
    {
        return 1;
    }

    return 0;
}


=head2 get

Get the value of a string-key.  Returns C<undef> if the key didn't exist,
or contain data.

=cut

sub get
{
    my ( $self, $key ) = (@_);

    if ( !$self->{ 'get' } )
    {
        $self->{ 'get' } =
          $self->{ 'db' }->prepare("SELECT val FROM string WHERE key=?");
    }
    $self->{ 'get' }->execute($key);
    my $x = $self->{ 'get' }->fetchrow_array();
    $self->{ 'get' }->finish();
    return ($x);
}



=head2 getset

Update the value of a key, and return the previous value if any.

=cut

sub getset
{
    my ( $self, $key, $val ) = (@_);

    my $old = $self->get($key);
    $self->set( $key, $val );

    return ($old);
}


=head2 strlen

Return the length of the given value of the given key.

=cut

sub strlen
{
    my ( $self, $key ) = (@_);

    my $data = $self->get($key);
    if ( defined($data) )
    {
        return ( length($data) );
    }
    return 0;
}


=head2 set

Set the value of a string-key.

=cut

sub set
{
    my ( $self, $key, $val ) = (@_);

    if ( !$self->{ 'ins' } )
    {
        $self->{ 'ins' } =
          $self->{ 'db' }
          ->prepare("INSERT OR REPLACE INTO string (key,val) VALUES( ?,? )");
    }
    $self->{ 'ins' }->execute( $key, $val );
    $self->{ 'ins' }->finish();

}


=head2 type

Return the type of the named key.

=cut

sub type
{
    my ( $self, $key ) = (@_);


    my $sql = $self->{ 'db' }->prepare("SELECT key FROM string WHERE key=?");
    $sql->execute($key);
    my $x = $sql->fetchrow_array() || undef;
    $sql->finish();

    return 'string' if ($x);

    $sql = $self->{ 'db' }->prepare("SELECT key FROM sets WHERE key=?");
    $sql->execute($key);
    $x = $sql->fetchrow_array() || undef;
    $sql->finish();

    return 'set' if ($x);

    return undef;
}


=head2 incr

Increment and return the value of an (integer) string-key.

=cut

sub incr
{
    my ( $self, $key ) = (@_);

    return ( $self->incrby( $key, 1 ) );
}



=head2 incrby

Increment and return the value of an (integer) string-key.

=cut

sub incrby
{
    my ( $self, $key, $amt ) = (@_);

    $amt = 1 if ( !defined($amt) );

    my $cur = $self->get($key) || 0;
    $cur += $amt;
    $self->set( $key, $cur );

    return ($cur);
}


=head2 decr

Decrement and return the value of an (integer) string-key.

=cut

sub decr
{
    my ( $self, $key ) = (@_);

    return ( $self->decrby( $key, 1 ) );
}



=head2 decrby

Decrement and return the value of an (integer) string-key.

=cut

sub decrby
{
    my ( $self, $key, $amt ) = (@_);

    $amt = 1 if ( !defined($amt) );

    my $cur = $self->get($key) || 0;
    $cur -= $amt;
    $self->set( $key, $cur );

    return ($cur);
}


=head2 del

Delete a given key, regardless of whether it holds a string or a set.

=cut

sub del
{
    my ( $self, $key ) = (@_);

    # strings
    my $str = $self->{ 'db' }->prepare("DELETE FROM string WHERE key=?");
    $str->execute($key);
    $str->finish();

    # Deleted a string-keyu
    return 1 if ( $str->rows > 0 );

    # sets
    my $set = $self->{ 'db' }->prepare("DELETE FROM sets WHERE key=?");
    $set->execute($key);
    $set->finish();

    # Deleted a set-key.
    return 1 if ( $set->rows > 0 );

    # Deleted nothing.
    return 0;
}


=head2 keys

Return the names of each known key.

These can be optionally filtered by a (perl) regular expression, for example:

=for example begin

   $redis->set( "foo", 1 );
   $redis->set( "moo", 1 );

   $redis->keys( "^f" );   # -> [ "foo" ]
   $redis->keys( "oo\$" ); # -> [ "foo", "moo" ]

=for example end

=cut

sub keys
{
    my ( $self, $pattern ) = (@_);

    # Get all keys into this hash
    my %known;

    # We run the same query against two tables.
    foreach my $table (qw! string sets !)
    {
        # Get the names of the key.
        my $str = $self->{ 'db' }->prepare("SELECT key FROM $table");
        $str->execute();
        while ( my ($name) = $str->fetchrow_array )
        {
            $known{ $name } += 1;
        }
        $str->finish();
    }

    # The keys we've found
    my @keys = keys %known;

    if ($pattern)
    {
        my @ret;
        foreach my $ent (@keys)
        {
            push( @ret, $ent ) if ( $ent =~ /$pattern/ );
        }
        return (@ret);
    }
    else
    {
        return (@keys);
    }
}


=head2 smembers

Return the members of the given set.

=cut

sub smembers
{
    my ( $self, $key ) = (@_);

    if ( !$self->{ 'smembers' } )
    {
        $self->{ 'smembers' } =
          $self->{ 'db' }->prepare("SELECT val FROM sets WHERE key=?");
    }
    $self->{ 'smembers' }->execute($key);

    my @vals;
    while ( my ($name) = $self->{ 'smembers' }->fetchrow_array )
    {
        push( @vals, $name );
    }
    $self->{ 'smembers' }->finish();

    return (@vals);
}


=head2 smove

Move a member from a given set to a new one.

=cut

sub smove
{
    my ( $self, $src, $dst, $ent ) = (@_);

    # Get the value from the original set
    my $sql = $self->{ 'db' }
      ->prepare("UPDATE sets SET key=? WHERE ( key=? AND val=?)");

    $sql->execute( $dst, $src, $ent );
    $sql->finish();

    if ( $sql->rows > 0 )
    {
        return 1;
    }
    return 0;

}


=head2 sismember

Is the given item a member of the set?

=cut

sub sismember
{
    my ( $self, $set, $key ) = (@_);

    my $sql =
      $self->{ 'db' }->prepare("SELECT val FROM sets WHERE key=? AND val=?");
    $sql->execute( $set, $key );

    my $x = $sql->fetchrow_array() || undef;
    $sql->finish();

    if ( defined($x) && ( $x eq $key ) )
    {
        return 1;
    }
    return 0;
}


=head2 sadd

Add a member to a set.

=cut

sub sadd
{
    my ( $self, $key, $val ) = (@_);

    if ( !$self->{ 'sadd' } )
    {
        $self->{ 'sadd' } =
          $self->{ 'db' }->prepare(
            "INSERT INTO sets (key,val) SELECT ?,? WHERE NOT EXISTS( SELECT key, val FROM sets WHERE key=? AND val=? );"
          );

    }
    $self->{ 'sadd' }->execute( $key, $val, $key, $val );
    $self->{ 'sadd' }->finish();

    if ( $self->{ 'sadd' }->rows > 0 )
    {
        return 1;
    }
    return 0;

}


=head2 srem

Remove a member from a set.

=cut

sub srem
{
    my ( $self, $key, $val ) = (@_);

    if ( !$self->{ 'srem' } )
    {
        $self->{ 'srem' } =
          $self->{ 'db' }->prepare("DELETE FROM sets WHERE (key=? AND val=?)");
    }
    $self->{ 'srem' }->execute( $key, $val );
    $self->{ 'srem' }->finish();

    if ( $self->{ 'srem' }->rows > 0 )
    {
        return 1;
    }
    return 0;
}


=head2 spop

Remove a given number of elements from the named set, and return them.

=cut

sub spop
{
    my ( $self, $key, $count ) = (@_);

    $count = 1 if ( !defined($count) );

    my @res;

    while ( ( $count > 0 ) && ( $count <= $self->scard($key) ) )
    {
        my $rand = $self->srandmember($key);
        push( @res, $rand );
        $self->srem( $key, $rand );

        $count -= 1;
    }

    return (@res);
}



=head2 srandmember

Fetch the value of a random member from a set.

=cut

sub srandmember
{
    my ( $self, $key ) = (@_);

    if ( !$self->{ 'srandommember' } )
    {
        $self->{ 'srandommember' } =
          $self->{ 'db' }->prepare(
                "SELECT val FROM sets where key=? ORDER BY RANDOM() LIMIT 1") or
          die "Failed to prepare";
    }
    $self->{ 'srandommember' }->execute($key);
    my $x = $self->{ 'srandommember' }->fetchrow_array() || "";
    $self->{ 'srandommember' }->finish();

    return ($x);
}


=head2 sunion

Return the values which are present in each of the sets named, duplicates
will only be returned one time.

For example:

=for example begin

   $redis->sadd( "one", 1 );
   $redis->sadd( "one", 2 );
   $redis->sadd( "one", 3 );

   $redis->sadd( "two", 2 );
   $redis->sadd( "two", 3 );
   $redis->sadd( "two", 4 );

   $redis->sunion( "one", "two" ); # -> [ 1,2,3,4 ]

=for example end

=cut

sub sunion
{
    my ( $self, @keys ) = (@_);


    my %result;

    foreach my $key (@keys)
    {
        my @vals = $self->smembers($key);
        foreach my $val (@vals)
        {
            $result{ $val } += 1;
        }
    }

    return ( CORE::keys(%result) );
}


=head2 sunionstore

Store the values which are present in each of the named sets in a new set.

=cut

sub sunionstore
{
    my ( $self, $dest, @keys ) = (@_);

    # Get the union
    my @union = $self->sunion(@keys);

    # Delete the current contents of the destination.
    $self->del($dest);

    # Now store the members
    foreach my $ent (@union)
    {
        $self->sadd( $dest, $ent );
    }

    # Return the number of entries added
    return ( scalar @union );
}


=head2 sinter

Return only those members who exist in each of the named sets.

=for example begin

   $redis->sadd( "one", 1 );
   $redis->sadd( "one", 2 );
   $redis->sadd( "one", 3 );

   $redis->sadd( "two", 2 );
   $redis->sadd( "two", 3 );
   $redis->sadd( "two", 4 );

   $redis->sinter( "one", "two" ); # -> [ 2,3 ]

=for example end

=cut

sub sinter
{
    my ( $self, @names ) = (@_);

    my %seen;

    foreach my $key (@names)
    {
        my @vals = $self->smembers($key);
        foreach my $val (@vals)
        {
            $seen{ $val } += 1;
        }
    }

    my @result;

    foreach my $key ( CORE::keys(%seen) )
    {
        if ( $seen{ $key } == scalar @names )
        {
            push( @result, $key );
        }
    }
    return (@result);
}



=head2 sinterstore

Store those members who exist in all the named sets in a new set.

=cut

sub sinterstore
{
    my ( $self, $dest, @names ) = (@_);

    # Get the values that intersect
    my @update = $self->sinter(@names);

    # Delete the current contents of the destination.
    $self->del($dest);

    # Now store the members
    foreach my $ent (@update)
    {
        $self->sadd( $dest, $ent );
    }

    # Return the number of entries added
    return ( scalar @update );
}


=head2 scard

Count the number of entries in the given set.

=cut

sub scard
{
    my ( $self, $key ) = (@_);

    if ( !$self->{ 'scard' } )
    {
        $self->{ 'scard' } =
          $self->{ 'db' }->prepare("SELECT COUNT(id) FROM sets where key=?");
    }
    $self->{ 'scard' }->execute($key);
    my $count = $self->{ 'scard' }->fetchrow_array() || 0;
    $self->{ 'scard' }->finish();

    return ($count);
}



our $AUTOLOAD;

sub AUTOLOAD
{
    my $command = $AUTOLOAD;
    $command =~ s/.*://;
    warn "NOT IMPLEMENTED:$command";

    return 1;
}

1;



=head1 AUTHOR

Steve Kemp

http://www.steve.org.uk/

=cut



=head1 LICENSE

Copyright (c) 2016 by Steve Kemp.  All rights reserved.

This module is free software;
you can redistribute it and/or modify it under
the same terms as Perl itself.
The LICENSE file contains the full text of the license.

=cut
