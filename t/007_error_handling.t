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

my ($cd, $db);

# START
# standard error handling
$db = ORMesque->new('dbi:SQLite:' . "$FindBin::Bin/001_database.db", "", "", {
    RaiseError => 0,
    PrintError => 0,
});

$cd = $db->cd;

eval {$cd->create({})};
ok $@, 'yup, always dies when called with no input';

eval {$cd->create({ blah => 'blah' })};
ok !$@, 'no die when raiseerror (dieness) is 0 and printerror (raise) is 1';

ok $cd->error, 'nice error was registered tho - (' . $cd->error . ')';
ok $db->error, 'main class error was registered also - (' . $db->error . ')';

# AGAIN
# quite no error handling
$db = ORMesque->new('dbi:SQLite:' . "$FindBin::Bin/001_database.db", "", "", {
    RaiseError => 0,
    PrintError => 0,
});

$cd = $db->cd;

eval {$cd->create({})};
ok $@, 'mandatory no input die';

eval {$cd->create({ blah => 'blah' })};
ok !$@, 'no die when raiseerror (dieness) is 0 and printerror (raise) is 0';

ok $cd->error, 'no nice error was registered which is good - (' . $cd->error . ')';
ok $db->error, 'main class error is non-exist also - (' . $db->error . ')';
