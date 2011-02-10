NAME
    ORMesque - Lightweight To-The-Point ORM

VERSION
    version 1.103190

SYNOPSIS
        my $db = ORMesque->new('dbi:mysql:foo', 'root');
    
        my $ta = $db->table_a
                ->page(1, 25)
                ->read({ column => 'value' });
    
        my $tb = $db->table_b
                ->page(1, 25)
                ->read({ column => 'value' });
    
        return to_json $ta->join($tb);

    ORMesque is a lightweight ORM for Dancer supporting any database listed
    under ORMesque::SchemaLoader making it a great alternative when you
    don't have the time, need or desire to learn DBIx::Class. ORMesque is an
    object relational mapper for Dancer that provides a database connection
    to the database of your choice and automatically creates objects and
    accessors for that database and its tables and columns. ORMesque uses
    SQL::Abstract querying syntax. More usage examples...

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

  dbi
        The dbi method/keyword instantiates a new ORMesque instance
        which uses the datasource configuration details in your configuration file
        to create database objects and accessors.
    
        my $db = ORMesque->new(...);

  reset
        Once the dbi() keyword analyzes the specified database, the schema is cached
        to for speed and performance. Occassionally you may want to re-read the
        database schema.
    
        $db->reset;
        my $db = ORMesque->new(...);

  next
        The next method instructs the database object to continue to the next
        row if it exists.
    
        $db->table->next;
    
        while ($db->table->next) {
            ...
        }

  first
        The first method instructs the database object to continue to return the first
        row in the resultset.
    
        $db->table->first;

  last
        The last method instructs the database object to continue to return the last
        row in the resultset.
    
        $db->table->last;

  collection
        The collection method return the raw resultset object.
    
        $db->table->collection;

  current
        The current method return the raw row resultset object of the position in
        the resultset collection.
    
        $db->table->current;

  clear
        The clear method empties all resultset containers. This method should be used
        when your ready to perform another operation (start over) without initializing
        a new object.
    
        $db->table->clear;

  key
        The key method finds the database objects primary key if its defined.
    
        $db->table->key;

  select
        The select method defines specific columns to be used in the generated
        SQL query. This useful for database tables that have lots of columns
        where only a few are actually needed.
    
        my $table = $db->select('foo', 'bar')->read();

  return
        The return method queries the database for the last created object(s).
        It is important to note that while return() can be used in most cases
        like the last_insert_id() to fetch the recently last created entry,
        function, you should not use it that way unless you know exactly what
        this method does and what your database will return.
    
        my $new_record = $db->table->create(...)->return();

  count
        The count method returns the number of items in the resultset of the
        object it's called on. Note! If you make changes to the database, you
        will need to call read() before calling count() to get an accurate
        count as count() operates on the current collection.
    
        my $count = $db->table->read->count;

  create
        Caveat 1: The create method will remove the primary key if the column
        is marked as auto-incremented ...
    
        The create method creates a new entry in the datastore.
        takes 1 arg: hashref (SQL::Abstract fields parameter)
    
        $db->table->create({
            'column_a' => 'value_a',
        });
    
        # create a copy of an existing record
        my $user = $db->users;
        $user->read;
        $user->full_name_column('Copy of ' . $user->full_name);
        $user->user_name_column('foobarbaz');
        $user->create($user->current);

        # get newly created record
        $user->return;
    
        print $user->id; # new record id
        print $user->full_name;

  read
        The read method fetches records from the datastore.
        Takes 2 arg.
    
        arg 1: hashref (SQL::Abstract where parameter) or scalar
        arg 2: arrayref (SQL::Abstract order parameter) - optional
    
        $db->table->read({
            'column_a' => 'value_a',
        });
    
        .. or read by primary key ..
    
        $db->table->read(1);
    
        .. or read and limit the resultset ..
    
        $db->table->read({ 'column_a' => 'value_a' }, ['orderby_column_a'], $limit, $offset);
    
        .. or return a paged resultset ..
    
        $db->table->page(1, 25)->read;

  update
        The update method alters an existing record in the datastore.
        Takes 2 arg.
    
        arg 1: hashref (SQL::Abstract fields parameter)
        arg 2: arrayref (SQL::Abstract where parameter) or scalar - optional
    
        $db->table->update({
            'column_a' => 'value_a',
        },{
            'where_column_a' => '...'
        });
    
        or
    
        $db->table->update({
            'column_a' => 'value_a',
        }, 1);

  delete
        The delete method is prohibited from deleting an entire database table and
        thus requires a where clause. If you intentionally desire to empty the entire
        database then you may use the delete_all method.
    
        $db->table->delete({
            'column_a' => 'value_a',
        });
    
        or
    
        $db->table->delete(1);

  delete_all
        The delete_all method is use to intentionally empty the entire database table.
    
        $db->table->delete_all;

  join
    If you have used ORMesque with a project of any sophistication you will
    have undoubtedly noticed that the is no mechanism for specifying joins
    and this is intentional. ORMesque is an ORM, and object relational
    mapper and that is its purpose, it is not a SQL substitute. Joins are
    neccessary in SQL as they are the only means of gathering related data.
    Such is not the case with Perl code, however, even in code the need to
    join related datasets exists and that is the need we address. The join
    method "Does Not Execute Any SQL", in-fact the join method is meant to
    be called after the desired resultsets have be gathered. The join method
    is merely an aggregator of result sets.

        my ($cd, $artist) = ($db->cd, $db->artist);

        $artist->read({ id => $aid });
        $cd->read({ artist => $aid });

    Always use the larger dataset to initiate the join, in the following
    example, the list we want is "the list of cds" and we want to include
    the artist information with every "cd" entry so we use the persist
    option.

        my $resultset = $cd->join($artist, {
            persist => 1
        });

    The join configuration option "persist" when set true will instruct the
    aggregator to include the first entry of the associated table with each
    entry in the primary list which is the list (collection) within the
    object that initiated the join. Every table object may be passed an
    options join configuration object as follows:

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

    By default, a joined resultset is returned as an arrayref of hashrefs
    with all table columns as keys which are in $table_$columnName format.
    This is not always ideal and so the "columns" join configuration option
    allows you to specify exactly which columns to include as well as supply
    an alias if desired. The following is an example of that:

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

  page
        The page method creates a paged resultset and instructs the read() method to
        only return the resultset of the desired page.
    
        my $page = 1; # page of data to be returned
        my $rows = 100; # number of rows to return
    
        $db->table->page($page, $rows)->read;

  pager
        The pager method provides access to the Data::Page object used in pagination.
        Please see L<Data::Page> for more details...
    
        $pager = $db->table->pager;
    
        $pager->first_page;
        $pager->last_page;

RESULTSET METHODS
    ORMesque provides columns accessors to the current record in the
    resultset object which is accessible via current() by default,
    collection() returns an arrayref of hashrefs based on the last read()
    call. Alternatively you may use the following methods to further
    transform and manipulate the returned resultset.

  columns
        Returns a list of column names. In scalar context, returns an array reference.
        Column names are lower cased if lc_columns was true when the query was executed.

  into
        Binds the columns returned from the query to variable(s)
    
        $db->table->read(1)->into(my ($foo, $bar));

  list
        Fetches a single row and returns a list of values. In scalar context,
        returns only the last value.
    
        my @values = $db->table->read(1)->list;

  array
        Fetches a single row and returns an array reference.
    
        my $row = $db->table->read(1)->array;
        print $row->[0];

  hash
        Fetches a single row and returns a hash reference.
        Keys are lower cased if lc_columns was true when the query was executed.
    
        my $row = $db->table->read(1)->hash;
        print $row->{id};

  flat
        Fetches all remaining rows and returns a flattened list.
        In scalar context, returns an array reference.
    
        my @records = $db->table->read(1)->flat;
        print $records[0];

  arrays
        Fetches all remaining rows and returns a list of array references.
        In scalar context, returns an array reference.
    
        my $rows = $db->table->read(1)->arrays;
        print $rows->[0];

  hashes
        Fetches all remaining rows and returns a list of hash references.
        In scalar context, returns an array reference.
        Keys are lower cased if lc_columns was true when the query was executed.
    
        my $rows = $db->table->read(1)->hashes;
        print $rows->[0]->{id};

  map_hashes
        Constructs a hash of hash references keyed by the values in the chosen column.
        In scalar context, returns a hash reference.
        In list context, returns interleaved keys and values.
    
        my $customer = $db->table->read->map_hashes('id');
        # $customers = { $id => { name => $name, location => $location } }

  map_arrays
        Constructs a hash of array references keyed by the values in the chosen column.
        In scalar context, returns a hash reference.
        In list context, returns interleaved keys and values.
    
        my $customer = $db->table->read->map_arrays(0);
        # $customers = { $id => [ $name, $location ] }

  rows
        Returns the number of rows affected by the last row affecting command,
        or -1 if the number of rows is not known or not available.
        For SELECT statements, it is generally not possible to know how many
        rows are returned. MySQL does provide this information. See DBI for a
        detailed explanation.
    
        my $changes = $db->table->insert($db->table->current)->rows;

UTILITIES
    ORMesque has as its sub-classes DBIx::Simple and SQL::Abstract as its
    querying language, it also provides access to SQL::Interp for good
    measure. For an in-depth look at what you can do with these utilities,
    please check out DBIx::Simple::Examples.

  query
    The query function provides a simplified interface to DBI, Perl's
    powerful database interfacing module. This function provides
    auto-escaping/interpolation as well as resultset abstraction.

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

  iquery
    The iquery function is used to interpolate Perl variables into SQL
    statements, it converts a list of intermixed SQL fragments and variable
    references into a conventional SQL string and list of bind values
    suitable for passing onto DBI

        my $result = $db->iquery('INSERT INTO table', \%item);
        my $result = $db->iquery('UPDATE table SET', \%item, 'WHERE y <> ', \2);
        my $result = $db->iquery('DELETE FROM table WHERE y = ', \2);

        # These two select syntax produce the same result
        my $result = $db->iquery('SELECT * FROM table WHERE x = ', \$s, 'AND y IN', \@v);
        my $result = $db->iquery('SELECT * FROM table WHERE', {x => $s, y => \@v});

        my $first_record = $result->hash;
        for ($result->hashes) { ... }

  dbix
    Access to the underlying DBIx::Simple object.

  dbi
    Access to the underlying DBI object.

  connected
    Determine whether a database connection exists. Returns true or false.

AUTHOR
    Al Newkirk <awncorp@cpan.org>

COPYRIGHT AND LICENSE
    This software is copyright (c) 2010 by awncorp.

    This is free software; you can redistribute it and/or modify it under
    the same terms as the Perl 5 programming language system itself.

