#ABSTRACT: ORMesque Database Schema Loader

package ORMesque::SchemaLoader;

use strict;
use warnings;

use DBI;

# VERSION

=head1 SYNOPSIS

ORMesque::SchemaLoader analyzes the target database's schema and
generates a blueprint L<Dancer::Plugin::ORMesque> uses to build objects and accessors.
Dancer::Plugin::ORMesque currently supports the following databases.

    * MySQL
    * SQLite
    * PostgreSQL

=cut

sub new {
    my ($class, $dbh) = @_;
    bless { dbh => $dbh }, $class;
}

sub mysql {
    my $self = shift;
    my $this = {};
    
    $this->{schema}->{escape_string} = '`';
    
    push @{$this->{schema}->{tables}}, $_->[0]
      foreach @{$self->{dbh}->selectall_arrayref("SHOW TABLES")};

    # load table columns
    foreach my $table (@{$this->{schema}->{tables}}) {
        for (@{$self->{dbh}->selectall_arrayref("SHOW COLUMNS FROM `$table`")}) {
            push @{$this->{schema}->{table}->{$table}->{columns}}, $_->[0];

            # find primary key
            $this->{schema}->{table}->{$table}->{primary_key} = $_->[0]
              if lc($_->[3]) eq 'pri';
        }
    }
    
    return $this;
}

sub sqlite {
    my $self = shift;
    my $this = {};
    
    $this->{schema}->{escape_string} = '"';
    
    # load tables
    push @{$this->{schema}->{tables}}, $_->[2] foreach @{
        $self->{dbh}->selectall_arrayref(
            "SELECT * FROM sqlite_master WHERE type='table'")
      };

    # load table columns
    foreach my $table (@{$this->{schema}->{tables}}) {
        for (@{$self->{dbh}->selectall_arrayref("PRAGMA table_info('$table')")}) {
            push @{$this->{schema}->{table}->{$table}->{columns}}, $_->[1];

            # find primary key
            $this->{schema}->{table}->{$table}->{primary_key} = $_->[1]
              if lc($_->[5]) == 1;
        }
    }

    return $this;
}

sub postgresql {
    my $self = shift;
    my $this = {};
    
    $this->{schema}->{escape_string} = "'";
    
    # load tables
    push @{$this->{schema}->{tables}}, $_->[0]
      foreach @{$self->{dbh}->selectall_arrayref("SELECT table_name FROM
        information_schema.tables WHERE table_schema = 'public' ")};

    # load table columns
    foreach my $table (@{$this->{schema}->{tables}}) {
        
        for (@{$self->{dbh}->selectall_arrayref("SELECT column_name FROM
            information_schema.columns WHERE table_name ='$table'")}) {
            
            push @{$this->{schema}->{table}->{$table}->{columns}}, $_->[0];
            
        }
        
        # get primary key
        my $pkey_query = qq|
        SELECT               
        pg_attribute.attname, 
        format_type(pg_attribute.atttypid, pg_attribute.atttypmod) 
        FROM pg_index, pg_class, pg_attribute 
        WHERE 
        pg_class.oid = '$table'::regclass AND
        indrelid = pg_class.oid AND
        pg_attribute.attrelid = pg_class.oid AND 
        pg_attribute.attnum = any(pg_index.indkey)
        AND indisprimary|;
        
        my $key = $self->{dbh}->selectall_arrayref($pkey_query);
        $this->{schema}->{table}->{$table}->{primary_key} = $key->[0]->[0];
        
    }
    
    return $this;
}

1;
