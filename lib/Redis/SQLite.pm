package Redis::SQLite;


use strict;
use warnings;
use DBI;


#
# Constructor
#
sub new
{
    my ( $proto, %supplied ) = (@_);
    my $class = ref($proto) || $proto;

    my $self = {};
    bless( $self, $class );

    # Create ~/.predis.db
    my $home = $ENV{'HOME'} || (getpwuid($<))[7];
    my $file = $supplied{ 'path' } || "$home/.predis.db";

    # Create the structure, if the file doesn't exist.
    my $create = 1;
    $create = 0 if ( -e $file );

    $self->{ 'db' } =
      DBI->connect( "dbi:SQLite:dbname=$file", "", "", { AutoCommit => 1 } );

    #
    #  Create the database tables if we should.
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


#
#  Get the value of a string-key.
#
sub get
{
    my ( $self, $key ) = (@_);

    if ( !$self->{ 'get' } )
    {
        $self->{ 'get' } =
          $self->{ 'db' }->prepare("SELECT val FROM string WHERE key=?");
    }
    $self->{ 'get' }->execute($key);
    my $x = $self->{ 'get' }->fetchrow_array() || undef;
    $self->{ 'get' }->finish();
    return ($x);
}



#
#  Set the value of a string-key.
#
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



#
#  Increment and return the value of an (integer) string-key.
#
sub incr
{
    my ( $self, $key, $amt ) = (@_);

    $amt = 1 if ( !defined($amt) );

    my $cur = $self->get($key) || 0;
    $cur += $amt;
    $self->set( $key, $cur );

    return ($cur);
}




#
#  Decrement and return the value of an (integer) string-key.
#
sub decr
{
    my ( $self, $key, $amt ) = (@_);

    $amt = 1 if ( !defined($amt) );

    my $cur = $self->get($key) || 0;
    $cur -= $amt;
    $self->set( $key, $cur );

    return ($cur);
}



#
#  Delete a string-key.
#
sub del
{
    my ( $self, $key ) = (@_);

    # strings
    my $str = $self->{ 'db' }->prepare("DELETE FROM string WHERE key=?");
    $str->execute($key);
    $str->finish();

    # sets
    my $set = $self->{ 'db' }->prepare("DELETE FROM sets WHERE key=?");
    $set->execute($key);
    $set->finish();

}



#
# Get members of the given set.
#
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
        push( @vals,  $name );
    }
    $self->{ 'smembers' }->finish();

    return (@vals);
}

#
#  Add a member to a set.
#
sub sadd
{
    my ( $self, $key, $val ) = (@_);

    if ( !$self->{ 'sadd' } )
    {
        $self->{ 'sadd' } =
          $self->{ 'db' }->prepare("INSERT INTO sets (key,val) SELECT ?,? WHERE NOT EXISTS( SELECT key, val FROM sets WHERE key=? AND val=? );");

    }
    $self->{ 'sadd' }->execute( $key, $val, $key, $val );
    $self->{ 'sadd' }->finish();
}


#
#  Remove a member from a set.
#
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
}


#
#  Fetch the value of a random member from a set.
#
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


#
#  Find the number of values in the set
#
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

#
#  End of the module.
#
1;
