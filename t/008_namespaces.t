package MyApp::Model::Cd;

sub get_a_cd {
    return 1;
}

# more realistic method
sub newcd_myway {
    my $self  = shift;
    my $title = shift;
    
    $self->create({ artist => -1, name => $title });
    
    return $self->return;
}

package MyApp::Model;
use base 'ORMesque';

use strict;
use warnings;
use Test::More import => ['!pass'];
use Test::Exception;
use FindBin;

BEGIN {
    eval { require DBD::SQLite };

    if ($@) {
        plan skip_all => 'DBD::SQLite is required to run these tests';
    }
    else {
        plan tests => 6;
    }

    use_ok 'ORMesque';
}

my ($cd, $db);

$db = MyApp::Model->new('dbi:SQLite:' . "$FindBin::Bin/001_database.db", "", "", {
    RaiseError => 0,
    PrintError => 1,
});

$cd = $db->cd;
ok 'MyApp::Model' eq $db->namespace, 'the MyApp::Model namespace has been set';
ok 'MyApp::Model' eq $cd->namespace, 'the MyApp::Model namespace is persistent';
ok $cd->get_a_cd(), 'the MyApp::Model class has a get_a_cd() method';
ok $cd->read->count, 'the MyApp::Model::Cd table has entries and can count';
ok ref($cd->newcd_myway('blah')), 'custom method returns as expected';

#use Data::Dumper qw/Dumper/;
#print Dumper $cd->newcd_myway('this is a test');
#print "$_\n" for keys %{MyApp::Model::Cd::};

1;