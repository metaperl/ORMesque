#ABSTRACT: Lightweight To-The-Point ORM

package ORMesque;

use strict;
use warnings;
use ORMesque::DBIxSimpleHack;    # mod'd dbix-simple to use S::A::L
use base 'DBIx::Simple';

use ORMesque::SchemaLoader;

use SQL::Abstract;
use SQL::Interp;

use Data::Page;

our $Cache = undef;

# VERSION

=head1 SYNOPSIS

    my $db = ORMesque->new('dbi:mysql:foo', 'root');
    
    my $ta = $db->table_a
            ->page(1, 25)
            ->read({ column => 'value' });
    
    my $tb = $db->table_b
            ->page(1, 25)
            ->read({ column => 'value' });
    
    return $ta->join($tb); # returns an aggregated arrayref of hashefs
    

ORMesque is a lightweight ORM supporting any database listed under
L<ORMesque::SchemaLoader> making it a great alternative when you don't have
the time, need or desire to learn/utilize L<DBIx::Class> or the like. ORMesque
is an object relational mapper that provides a database connection to the
database of your choice and automatically creates objects and accessors for that
database and its tables and columns. ORMesque uses L<SQL::Abstract> querying
syntax. More usage examples...
    
    my $db = ORMesque->new($dsn);
    
    my $user = $db->users;
    
    # Grab the first record, not neccessary if operating on only one record
    
    $user->read;
    
    # SQL::Abstract where clause passed to the "read" method
    
    $user->read({
        'column' => 'query'
    });
    
    $user->first;
    $user->last;
    
    # How many records in collection
    
    $user->count
    
    for (0..$user->count) {
        print $user->column;
        $user->column('new stuff');
        $user->update($user->current, $user->id);
        $user->next;
    }
    
    # The database objects main accessors are CRUD (create, read, update, and delete)
    
    $user->create;
      $user->read;
        $user->update;
          $user->delete;
    
    # Also, need direct access to the resultset?
    
    $user->collection; # returns an array of hashrefs
    $user->current;    # return a hashref of the current row in the collection
    
Occassionally you may want to create application Models using ORMesque and venture
beyond the standard CRUD methods, creating classes for each table and extending its
methods. The following is an example of how this should be done using ORMesque.

    package MyApp::Model;
    use base 'ORMesque';
    # create your base Model - lib/MyApp/Model.pm
    
    package MyApp::Model::Cd;
    use base 'MyApp::Model';
    # create your table specific Model - lib/MyApp/Model/Cd.pm
    # note the model should be named after the table, the naming is as follows:
    
    # Schema Table Classes are CamelCased for convention, all class names are
    # titlecased, and have dashed and underscores removed.
    
    # e.g. table 'user_workplace' would generate a class named 'UserWorkspace'
    
    # with no special characters. If package name is one of the auto-generated
    # classes, all relevant methods and settings will be set automatically.
    
    sub write_cd {
        $self = shift;
        ...
        $self->create({ ... });
        return $self;
    }
    
    ...
    
    1;
    
=cut

sub new {
    my $class = shift;

    return $Cache if $Cache;

    my @dsn = @_;
    my $nsp = undef;
    
    # check if a namespace has been defined
    if (ref $dsn[$#dsn]) {
        if (defined $dsn[$#dsn]->{NameSpace}) {
            $nsp = $dsn[$#dsn]->{NameSpace};
            delete $dsn[$#dsn]->{NameSpace};
        }
    }

    my $dbh = ORMesque->connect(@dsn) or die $DBI::errstr;
    my $cfg = {driver => $dbh->{dbh}->get_info(17)};

    die "Can't make out your database driver" unless $cfg->{driver};

    my $self = {};
    my $this = {};

    bless $self, $class;
    
    # explicitly set the namespace
    defined $nsp ? $self->namespace($nsp) : $self->namespace($class);

    warn "Error connecting to the database..." unless $dbh;
    warn "No database driver specified in the configuration file"
      unless $cfg->{driver};

    # POSTGRESQL CONFIGURATION
    $this = ORMesque::SchemaLoader->new($dbh->{dbh})->mysql
      if lc($cfg->{driver}) =~ '^postgre(s)?(ql)?$';

    # MYSQL CONFIGURATION
    $this = ORMesque::SchemaLoader->new($dbh->{dbh})->mysql
      if lc($cfg->{driver}) eq 'mysql';

    # SQLite CONFIGURATION
    $this = ORMesque::SchemaLoader->new($dbh->{dbh})->sqlite
      if lc($cfg->{driver}) eq 'sqlite';

    $self->{schema} = $this->{schema};
    die "Could not read the specified database $cfg->{driver}"
      unless @{$self->{schema}->{tables}};

    # setup reuseable connection using DBIx::Simple
    $self->{dbh} = DBIx::Simple->connect($dbh->{dbh}) or die DBIx::Simple->error;
    $self->{dbh}->result_class = 'DBIx::Simple::Result';
    $self->{dsn} = [@dsn];

    # define defaults
    $self->{target} = '';

    # create base accessors
    no warnings 'redefine';
    no strict 'refs';

    foreach my $table (@{$self->{schema}->{tables}}) {

        my $class        = $self->namespace;
        my $method       = $class . "::" . lc $table;
        my $classtable   = $table;
           
           if ($classtable =~ /[\-\_]/) {
                $classtable = join '', map { ucfirst lc $_ }
                    split /[\-\_]/, $classtable;
           }
           else {
                $classtable = ucfirst lc $classtable;
           }
        
        my $package_name = $class . "::" . $classtable;
        my $package      = "package $package_name;" . q|
            
            use base '| . $class . q|';
            
            sub new {
                my ($class, $base, $table) = @_;
                my $self            = {};
                bless $self, $class;
                $self->{table}      = $table;
                $self->{columns}    = $base->{schema}->{table}->{$table}->{columns};
                $self->{where}      = {};
                $self->{order}      = [];
                $self->{key}        = $base->{schema}->{table}->{$table}->{primary_key};
                $self->{collection} = [];
                $self->{cursor}     = 0;
                $self->{current}    = {};
                $self->{namespace}  = $base->{namespace};
                $self->{schema}     = $base->{schema};
                $self->{dbh}        = $base->dbix();
                $self->{dsn}        = $base->{dsn};
                
                # build database objects
                $self->{configuration} = $cfg;
                
                foreach my $column (@{$self->{schema}->{table}->{$table}->{columns}}) {
                    $self->{current}->{$column} = '';
                    my $attribute = $class . "::" . $column;
                    *{$attribute} = sub {
                        my ($self, $data) = @_;
                        if (defined $data) {
                            $self->{current}->{$column} = $data;
                            return $data;
                        }
                        else {
                            return
                                $self->{current}->{$column};
                        }
                    };
                }
                
                return $self;
            }
            1;
            |;
        eval $package;
        die print $@ if $@;    # debugging
        *{$method} = sub {
            return $package_name->new($self, $table);
        };

        # build dbo table

    }

    $Cache = $self;
    return $self;
}

sub _protect_sql {
    my ($dbo, @sql) = @_;
    
    return @_ unless $dbo->{schema}->{escape_string};
    
    # set field delimiters
    my ($stag, $etag) =
      length($dbo->{schema}->{escape_string}) == 1
      ? ($dbo->{schema}->{escape_string}, $dbo->{schema}->{escape_string})
      : split //, $dbo->{schema}->{escape_string};
      
    my $params = {};

    if ("HASH" eq ref $sql[0]) {
        $params = {
            map {
                if ($_ =~ /[^a-zA-Z\_0-9\s]/) {
                    ( $_ => $sql[0]->{$_} )
                }
                else {
                    ( "$stag$_$etag" => $sql[0]->{$_} )
                }
            }   keys %{$sql[0]}
        };
    }
    else {
        $params = [ map {
            if ($_ =~ /[^a-zA-Z\_0-9\s]/) {
                ($_)
            }
            else {
                "$stag$_$etag"
            }
        }   @sql ];
    }
    
    return "ARRAY" eq ref $params ? ( @{ $params } ) : $params;
}

=head2 namespace

    The namespace() method returns the classname being used in the auto-generated
    database table classes. 
    
    my $a = ORMesque->new(...);
    my $b = ThisApp->new(...);
    
    $a->namespace; # ORMesque
    $b->namespace; # ThisApp

=cut

sub namespace {
    my ($dbo, $namespace) = @_;
    $dbo->{namespace} = $namespace if defined $namespace;
    return $dbo->{namespace};
}

=head2 reset

    Once the reset() method analyzes the specified database, the schema is cached
    to for speed and performance. Occassionally you may want to re-read the
    database schema.
    
    my $db = ORMesque->new(...);
    $db->reset;

=cut

sub reset {
    $Cache = undef;
}

=head2 next

    The next() method instructs the database object to continue to the next
    row if it exists.
    
    my $table = ORMesque->new(...)->table;
    
    while ($table->next) {
        ...
    }

=cut

sub next {
    my $dbo = shift;
    
    $dbo->{collection} ||= [];
    
    my $next =
    $dbo->{cursor} <= (scalar(@{$dbo->{collection}}) - 1) ? $dbo : undef;
    $dbo->{current} = $dbo->{collection}->[$dbo->{cursor}] || {};
    $dbo->{cursor}++;

    return $next;
}

=head2 first

    The first() method instructs the database object to continue to return the first
    row in the resultset.
    
    my $table = ORMesque->new(...)->table;
    $table->first;

=cut

sub first {
    my $dbo = shift;

    $dbo->{cursor} = 0;
    $dbo->{current} = $dbo->{collection}->[0] || {};

    return $dbo->current;
}

=head2 last

    The last() method instructs the database object to continue to return the last
    row in the resultset.
    
    my $table = ORMesque->new(...)->table;
    $table->last;

=cut

sub last {
    my $dbo = shift;

    $dbo->{cursor} = (scalar(@{$dbo->{collection}}) - 1);
    $dbo->{current} = $dbo->{collection}->[$dbo->{cursor}] || {};

    return $dbo->current;
}

=head2 collection

    The collection() method return the raw resultset object.
    
    my $table = ORMesque->new(...)->table;
    $table->collection;

=cut

sub collection {
    return shift->{collection};
}

=head2 current

    The current() method return the raw row resultset object of the position in
    the resultset collection.
    
    my $table = ORMesque->new(...)->table;
    $table->current;

=cut

sub current {
    return shift->{current};
}

=head2 clear

    The clear() method empties all resultset containers. This method should be used
    when your ready to perform another operation (start over) without initializing
    a new object.
    
    my $table = ORMesque->new(...)->table;
    $table->clear;

=cut

sub clear {
    my $dbo = shift;

    foreach my $column (keys %{$dbo->{current}}) {
        $dbo->{current}->{$column} = '';
    }

    $dbo->{collection} = [];

    return $dbo;
}

=head2 key

    The key() method finds the database objects primary key if its defined.
    
    my $table = ORMesque->new(...)->table;
    $table->key;

=cut

sub key {
    shift->{key};
}

=head2 select

    The select() method defines specific columns to be used in the generated
    SQL query. This useful for database tables that have lots of columns
    where only a few are actually needed.
    
    my $table = ORMesque->new(...)->table
    $table->select('foo', 'bar')->read();

=cut

sub select {
    my $dbo = shift;

    $dbo->{select} = [@_] if @_;

    return $dbo;
}

=head2 return

    The return() method queries the database for the last created object(s).
    It is important to note that while return() can be used in most cases
    like the last_insert_id() to fetch the recently last created entry,
    function, you should not use it that way unless you know exactly what
    this method does and what your database will return.
    
    my $new = ORMesque->new(...)->table;
    $new->create(...);
    $new->return();
    $new->column
    
    ..or..
    
    my $rec = $new->current; # current row

=cut

sub return {
    my $dbo   = shift;
    my %where = %{$dbo->current};

    delete $where{$dbo->key} if $dbo->key;

    $dbo->read(\%where)->last;

    return $dbo;
}

=head2 count

    The count() method returns the number of items in the resultset of the
    object it's called on. Note! If you make changes to the database, you
    will need to call read() before calling count() to get an accurate
    count as count() operates on the current collection.
    
    my $db = ORMesque->new(...)->table;
    my $count = $db->read->count;
    
    Note! The count() method DOES NOT query the database, it merely counts
    the number of items in the existing resultset produced by read().
    Alternatively, to perform a type-of SQL COUNT() query you can use the
    count($where) syntax:
    
    my $db = ORMesque->new(...)->table;
    my $count = $db->count({ id => 12345});
    # notice there is no read() command

=cut

sub count {
    my $dbo = shift;
    my $whr = shift;
    
    if (defined $whr) {
        my @columns = $dbo->_protect_sql($dbo->key || '*');
        my $counter = 'COUNT('. $columns[0] .')';
        $dbo->select($counter)->read($whr);
        return scalar $dbo->list;
    }
    
    return scalar @{$dbo->{collection}};
}

=head2 create

    Caveat 1: The create method will remove the primary key if the column
    is marked as auto-incremented ...
    
    The create method creates a new entry in the datastore.
    takes 1 arg: hashref (SQL::Abstract fields parameter)
    
    ORMesque->new(...)->table->create({
        'column_a' => 'value_a',
    });
    
    # create a copy of an existing record
    my $user = ORMesque->new(...)->users;
    $user->read;
    $user->full_name_column('Copy of ' . $user->full_name);
    $user->user_name_column('foobarbaz');
    $user->create($user->current);

    # get newly created record
    $user->return;
    
    print $user->id; # new record id
    print $user->full_name;
=cut

sub create {
    my $dbo     = shift;
    my $input   = shift || {};
    my @columns = $dbo->_protect_sql(@{$dbo->{columns}});

    die
      "Cannot create an entry in table ($dbo->{table}) without any input parameters."
      unless keys %{$input};

    # add where clause to current for
    # $dbo->create(..); $dbo->return; operations
    if ($input) {
        foreach my $i (keys %{$input}) {
            if (defined $dbo->{current}->{$i}) {
                $dbo->{current}->{$i} = $input->{$i};
            }
        }
    }

    # insert
    $dbo->dbix
      ->insert($dbo->_protect_sql($dbo->{table}), $dbo->_protect_sql($input));

    return $dbo->error ? 0 : 1;
}

=head2 read

    The read method fetches records from the datastore.
    Takes 2 arg.
    
    arg 1: hashref (SQL::Abstract where parameter) or scalar
    arg 2: arrayref (SQL::Abstract order parameter) - optional
    
    ORMesque->new(...)->table->read({
        'column_a' => 'value_a',
    });
    
    .. or read by primary key ..
    
    ORMesque->new(...)->table->read(1);
    
    .. or read and limit the resultset ..
    
    ORMesque->new(...)->table->read({ 'column_a' => 'value_a' }, ['orderby_column_a'], $limit, $offset);
    
    .. or return a paged resultset ..
    
    ORMesque->new(...)->table->page(1, 25)->read;

=cut

sub read {
    my $dbo = shift;

    my $tables = [];

    if ("ARRAY" eq ref $_[0]) {
        $tables = shift;
    }

    my $where = shift || {};
    my $order = shift || [];
    my $table = $dbo->{table};
    my @columns = ();

    my ($limit, $offset) = @_;

    if (defined $dbo->{select}) {
        @columns = $dbo->_protect_sql(@{$dbo->{select}});
    }
    else {
        @columns = $dbo->_protect_sql(@{$dbo->{columns}});
    }

    # generate a where primary_key = ? clause
    if ($where && ref($where) ne "HASH") {
        $where = {$dbo->key => $where};
    }

    if ($limit || $offset || $dbo->{ispaged}) {

        if ($dbo->{ispaged}) {
            $dbo->{ispaged} = 0;
            $dbo->pager->total_entries($dbo->dbix
                  ->select($table, 'COUNT(*)', $dbo->_protect_sql($where))
                  ->array->[0]);
            ($offset, $limit) =
              ($dbo->pager->skipped, $dbo->pager->entries_per_page);
        }

        $dbo->{resultset} = sub {
            return $dbo->dbix->select(
                join(',',
                    $dbo->_protect_sql($table),
                    map { $dbo->_protect_sql($_) } @{$tables}),
                \@columns,
                $dbo->_protect_sql($where),
                $order, $limit, $offset
            );
        };
    }
    else {
        $dbo->{resultset} = sub {
            return $dbo->dbix->select(
                join(',',
                    $dbo->_protect_sql($table),
                    map { $dbo->_protect_sql($_) } @{$tables}),
                \@columns,
                $dbo->_protect_sql($where),
                $order
            );
        };
    }

    if (defined $dbo->{select}) {
        
        # create a fiticious collection :/
        
        $dbo->{collection} = [

            map {
                foreach my $i (keys %{$dbo->{current}})
                {
                    unless (defined $_->{$i}) {
                        $_->{$i} = '';
                    }
                }

                $_
              }

              @{$dbo->{resultset}->()->hashes}
        ];
        
    }
    else {
        $dbo->{collection} = $dbo->{resultset}->()->hashes;
    }

    $dbo->{cursor} = 0;
    $dbo->next;
    
    $dbo->{select} = undef if defined $dbo->{select};

    return $dbo->error ? 0 : $dbo;
}

=head2 update

    The update method alters an existing record in the datastore.
    Takes 2 arg.
    
    arg 1: hashref (SQL::Abstract fields parameter)
    arg 2: arrayref (SQL::Abstract where parameter) or scalar - optional
    
    ORMesque->new(...)->table->update({
        'column_a' => 'value_a',
    },{
        'where_column_a' => '...'
    });
    
    or
    
    ORMesque->new(...)->table->update({
        'column_a' => 'value_a',
    }, 1);

=cut

sub update {
    my $dbo     = shift;
    my $input   = shift || {};
    my $where   = shift || {};
    my $table   = $dbo->{table};
    my @columns = $dbo->_protect_sql(@{$dbo->{columns}});

    # process direct input
    die
      "Attempting to update an entry in table ($dbo->$table) without any input."
      unless keys %{$input};

    # generate a where primary_key = ? clause
    if ($where && ref($where) ne "HASH") {
        $where = {$dbo->key => $where};
    }

    $dbo->dbix->update(
        $dbo->_protect_sql($table),
        $dbo->_protect_sql($input),
        $dbo->_protect_sql($where)
    ) if keys %{$input};

    return $dbo->error ? 0 : 1;
}

=head2 delete

    The delete method is prohibited from deleting an entire database table and
    thus requires a where clause. If you intentionally desire to empty the entire
    database then you may use the delete_all method.
    
    ORMesque->new(...)->table->delete({
        'column_a' => 'value_a',
    });
    
    or
    
    ORMesque->new(...)->table->delete(1);

=cut

sub delete {
    my $dbo   = shift;
    my $where = shift || {};
    my $table = $dbo->{table};

    # process where clause
    if (ref($where) eq "HASH") { }
    elsif ($where && $dbo->key && ref($where) ne "HASH") {
        $where = {$dbo->key => $where};
    }
    else {
        die "Cannot delete without a proper where clause, "
          . "use delete_all to purge the entire database table";
    }

    $dbo->dbix
      ->delete($dbo->_protect_sql($table), $dbo->_protect_sql($where));

    return $dbo->error ? 0 : 1;
}

=head2 delete_all

    The delete_all method is use to intentionally empty the entire database table.
    
    ORMesque->new(...)->table->delete_all;

=cut

sub delete_all {
    my $dbo   = shift;
    my $table = $dbo->{table};

    $dbo->dbix->delete($dbo->_protect_sql($table));

    return $dbo->error ? 0 : 1;
}

=head2 join

If you have used ORMesque with a project of any sophistication
you will have undoubtedly noticed that the is no mechanism for specifying joins
and this is intentional. ORMesque is an ORM, and object relational
mapper and that is its purpose, it is not a SQL substitute. Joins are neccessary
in SQL as they are the only means of gathering related data. Such is not the case
with Perl code, however, even in code the need to join related datasets exists and
that is the need we address. The join method "Does Not Execute Any SQL", in-fact
the join method is meant to be called after the desired resultsets have be gathered.
The join method is merely an aggregator of result sets.

    my ($cd, $artist) = (ORMesque->new(...)->cd, ORMesque->new(...)->artist);

    $artist->read({ id => $aid });
    $cd->read({ artist => $aid });
    
Always use the larger dataset to initiate the join, in the following example, the
list we want is "the list of cds" and we want to include the artist information with
every "cd" entry so we use the persist option.
    
    my $resultset = $cd->join($artist, {
        persist => 1
    });
    
The join configuration option "persist" when set true will instruct the aggregator to
include the first entry of the associated table with each entry in the primary list
which is the list (collection) within the object that initiated the join. Every
table object may be passed an options join configuration object as follows:

    my $resultset = $cd->join($artist, {
        persist => 1
    });
    
    .. which is the same as ..
    
    my $resultset = $cd->join({
    }, $artist, {
        persist => 1
    });
    
    .. more complexity ..
    
    my $resultset = $track->join($cd, {
        persist => 1
    }, $artist, {
        persist => 1
    });
    
By default, a joined resultset is returned as an arrayref of hashrefs with all table
columns as keys which are in $table_$columnName format. This is not always ideal and
so the "columns" join configuration option allows you to specify exactly which columns
to include as well as supply an alias if desired. The following is an example of that:

    my $resultset = $track->join({
        columns => {
            track_name => 'track',
        }
    }, $cd, {
        persist => 1
        columns => {
            cd_name => 'cd',
        }
    }, $artist, {
        persist => 1,
        columns => {
            artist_name => 'artist'
        }
    });

=cut

sub join {
    my $dbo = shift;

    die 'Join is meant to be called on ORMesque objects with table definitions'
      unless $dbo->{table};

    my @objs = @_;
    my $rs   = [];
    my $q    = 0;

    unshift @objs, $dbo;

    my @tmps = ();

    for (my $i = 0; $i < @objs; $i++) {
        if ("HASH" eq ref $objs[$i]) {
            $tmps[$#tmps]->{join_configuration} = $objs[$i];
        }
        else {
            $objs[$i]->{join_configuration} = {};
            push @tmps, $objs[$i];
        }
    }

    @objs = @tmps;

    if (@objs > 1) {
        foreach my $obj (@objs) {
            die 'Invalid ORMesque object passed to join'
              unless $obj->{table} && $obj->{collection};
        }

        # use the first object to set the length of the aggregator
        for (my $i = 0; $i < scalar(@{$objs[0]->{collection}}); $i++) {
            my $aggregate = {};
            for (my $y = 0; $y < @objs; $y++) {
                my $cfg = $objs[$y]->{join_configuration};
                my $rec = $objs[$y]->{collection}->[$i];
                if (keys %{$objs[$y]->{join_configuration}}) {
                    if ($cfg->{persist}) {
                        $rec = $objs[$y]->{collection}->[0];
                    }
                }
                my $new = {
                    map { $objs[$y]->{table} . "_" . $_ => $rec->{$_} }
                      keys %{($rec || $objs[$y]->{current})}
                };
                if ($cfg->{columns}) {
                    my $xchg = {};
                    foreach (keys %{$cfg->{columns}}) {
                        $xchg->{$cfg->{columns}->{$_}} = $new->{$_};
                    }
                    $new = $xchg;
                }
                $aggregate = {%{$aggregate}, %{$new}};
            }
            $rs->[$q++] = $aggregate;
        }
        return $rs;
    }
    else {
        die 'Please supply two or more ORMesque objects which may include the '
          . 'invoking object (self) before performing a join';
    }
}

=head2 page

    The page method creates a paged resultset and instructs the read() method to
    only return the resultset of the desired page.
    
    my $page = 1; # page of data to be returned
    my $rows = 100; # number of rows to return
    
    ORMesque->new(...)->table->page($page, $rows)->read;

=cut

sub page {
    my $dbo = shift;
    die 'The page method requires a page number and number of rows to return'
      unless @_ == 2;

    $dbo->{ispaged} = 1;

    $dbo->pager->current_page($_[0]);
    $dbo->pager->entries_per_page($_[1]);

    return $dbo;
}

=head2 pager

    The pager method provides access to the Data::Page object used in pagination.
    Please see L<Data::Page> for more details...
    
    $pager = ORMesque->new(...)->table->pager;
    
    $pager->first_page;
    $pager->last_page;

=cut

sub pager {
    my $dbo = shift;
    $dbo->{pager} ||= Data::Page->new(@_);
}

=head1 RESULTSET METHODS

ORMesque provides columns accessors to the current record in the
resultset object which is accessible via current() by default, collection()
returns an arrayref of hashrefs based on the last read() call. Alternatively you
may use the following methods to further transform and manipulate the returned
resultset.

=cut

=head2 columns

    Returns a list of column names. In scalar context, returns an array reference.
    Column names are lower cased if lc_columns was true when the query was executed.

=cut

sub columns {
    shift->{resultset}->()->columns(@_);
}

=head2 into

    Binds the columns returned from the query to variable(s)
    
    ORMesque->new(...)->table->read(1)->into(my ($foo, $bar));

=cut

sub into {
    return shift->{resultset}->()->into(@_);
}

=head2 list

    Fetches a single row and returns a list of values. In scalar context,
    returns only the last value.
    
    my @values = ORMesque->new(...)->table->read(1)->list;

=cut

sub list {
    return shift->{resultset}->()->list(@_);
}

=head2 array

    Fetches a single row and returns an array reference.
    
    my $row = ORMesque->new(...)->table->read(1)->array;
    print $row->[0];

=cut

sub array {
    return shift->{resultset}->()->array(@_);
}

=head2 hash

    Fetches a single row and returns a hash reference.
    Keys are lower cased if lc_columns was true when the query was executed.
    
    my $row = ORMesque->new(...)->table->read(1)->hash;
    print $row->{id};

=cut

sub hash {
    return shift->{resultset}->()->hash(@_);
}

=head2 flat

    Fetches all remaining rows and returns a flattened list.
    In scalar context, returns an array reference.
    
    my @records = ORMesque->new(...)->table->read(1)->flat;
    print $records[0];

=cut

sub flat {
    return shift->{resultset}->()->flat(@_);
}

=head2 arrays

    Fetches all remaining rows and returns a list of array references.
    In scalar context, returns an array reference.
    
    my $rows = ORMesque->new(...)->table->read(1)->arrays;
    print $rows->[0];

=cut

sub arrays {
    return shift->{resultset}->()->arrays(@_);
}

=head2 hashes

    Fetches all remaining rows and returns a list of hash references.
    In scalar context, returns an array reference.
    Keys are lower cased if lc_columns was true when the query was executed.
    
    my $rows = ORMesque->new(...)->table->read(1)->hashes;
    print $rows->[0]->{id};

=cut

sub hashes {
    return shift->{resultset}->()->hashes(@_);
}

=head2 map_hashes

    Constructs a hash of hash references keyed by the values in the chosen column.
    In scalar context, returns a hash reference.
    In list context, returns interleaved keys and values.
    
    my $customer = ORMesque->new(...)->table->read->map_hashes('id');
    # $customers = { $id => { name => $name, location => $location } }

=cut

sub map_hashes {
    return shift->{resultset}->()->map_hashes(@_);
}

=head2 map_arrays

    Constructs a hash of array references keyed by the values in the chosen column.
    In scalar context, returns a hash reference.
    In list context, returns interleaved keys and values.
    
    my $customer = ORMesque->new(...)->table->read->map_arrays(0);
    # $customers = { $id => [ $name, $location ] }

=cut

sub map_arrays {
    return shift->{resultset}->()->map_arrays(@_);
}

=head2 rows

    Returns the number of rows affected by the last row affecting command,
    or -1 if the number of rows is not known or not available.
    For SELECT statements, it is generally not possible to know how many
    rows are returned. MySQL does provide this information. See DBI for a
    detailed explanation.
    
    my $changes = ORMesque->new(...)->table->insert(ORMesque->new(...)->table->current)->rows;

=cut

sub rows {
    return shift->{resultset}->()->rows(@_);
}

=head1 UTILITIES

ORMesque has as its sub-classes L<DBIx::Simple> and L<SQL::Abstract>
as its querying language, it also provides access to L<SQL::Interp> for good measure.
For an in-depth look at what you can do with these utilities, please check out
L<DBIx::Simple::Examples>.

=head2 error

The error function is used to access the $DBI::errstr variable.

=cut

sub error {
    my $dbo = shift;
    my $err = $dbo->{dbh}->error(@_);
       $err =~ s/^DBI error\:\s+//;
       $err =~ s/\n+/\, /g;
    return $err;
}

=head2 query

The query function provides a simplified interface to DBI, Perl's powerful
database interfacing module. This function provides auto-escaping/interpolation
as well as resultset abstraction.

    $db->query('DELETE FROM foo WHERE id = ?', $id);
    $db->query('SELECT 1 + 1')->into(my $two);
    $db->query('SELECT 3, 2 + 2')->into(my ($three, $four));

    $db->query(
        'SELECT name, email FROM people WHERE email = ? LIMIT 1',
        $mail
    )->into(my ($name, $email));
    
    # One big flattened list (primarily for single column queries)
    
    my @names = $db->query('SELECT name FROM people WHERE id > 5')->flat;
    
    # Rows as array references
    
    for my $row ($db->query('SELECT name, email FROM people')->arrays) {
        print "Name: $row->[0], Email: $row->[1]\n";
    }

=cut

sub query {
    return shift->dbix->query(@_);
}

=head2 iquery

The iquery function is used to interpolate Perl variables into SQL statements, it
converts a list of intermixed SQL fragments and variable references into a
conventional SQL string and list of bind values suitable for passing onto DBI

    my $result = $db->iquery('INSERT INTO table', \%item);
    my $result = $db->iquery('UPDATE table SET', \%item, 'WHERE y <> ', \2);
    my $result = $db->iquery('DELETE FROM table WHERE y = ', \2);

    # These two select syntax produce the same result
    my $result = $db->iquery('SELECT * FROM table WHERE x = ', \$s, 'AND y IN', \@v);
    my $result = $db->iquery('SELECT * FROM table WHERE', {x => $s, y => \@v});

    my $first_record = $result->hash;
    for ($result->hashes) { ... }

=cut

sub iquery {
    return shift->dbix->iquery(@_);
}

=head2 dbix

Access to the underlying L<DBIx::Simple> object.

=cut

sub dbix {
    my $dbo = shift;
    
    $dbo->{last_chk} ||= 0;
    
    if ((time - $dbo->{last_chk}) < 10) {
        return $dbo->{dbh};
    }
    else {
        if ($dbo->connected) {
            return $dbo->{dbh};
        }
        else {
            $dbo->{dbh} = DBIx::Simple->connect(@{$dbo->{dsn}})
              or die DBIx::Simple->error;
            $dbo->{last_chk} = time;
        }
    }

    return $dbo->{dbh};
}

=head2 dbi

Access to the underlying L<DBI> object.

=cut

sub dbi {
    return shift->dbix->{dbh};
}

=head2 connected

Determine whether a database connection exists. Returns true or false.

=cut

sub connected {
    my $dbo = shift;
    return unless $dbo->{dbh}->{dbh};
    if (int($dbo->{dbh}->{dbh}->ping)) {
        return 1;
    }
    else {
        my $ok = 0;
        eval { $ok = $dbo->{dbh}->{dbh}->do('select 1') };
        return $ok;
    }
    return 0;
}

1;
