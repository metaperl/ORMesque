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
        plan tests => 9;
    }

    use_ok 'ORMesque';
}

# standard error handling
my $db = ORMesque->new('dbi:SQLite:' . "$FindBin::Bin/001_database.db", "", "", {
    RaiseError => 0,
    PrintError => 0,
});

eval {$db->cd->create({})};
ok $@, 'yup, always dies when called with no input';
eval {$db->cd->create({ blah => 'blah' })};
ok !$@, 'no die when raiseerror is 0';
ok $db->cd->error, 'nice error was registered tho';

$db = ORMesque->new('dbi:SQLite:' . "$FindBin::Bin/001_database.db", "", "", {
    RaiseError => 1,
    PrintError => 0,
});

eval {$db->cd->create({ blah => 'blah' })};
ok $@, 'die exists raiseerror is 1';
ok $db->cd->error, 'nice error was registered too tho';

$db = ORMesque->new('dbi:SQLite:' . "$FindBin::Bin/001_database.db", "", "", {
    RaiseError => 1,
    PrintError => 1,
});

eval {$db->cd->create({ blah => 'blah' })};
ok $@, 'die when printerror and raiseerror is 1';
ok $db->cd->error, 'nice error was registered tho';

