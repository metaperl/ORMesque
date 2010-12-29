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

my $db = ORMesque->new('dbi:SQLite:' . "$FindBin::Bin/001_database.db");

my $cd = $db->cd;

ok "Data::Page" eq ref($cd->pager), 'pager set';
ok $cd->read({},[],2,1), 'limit no fail';

#$cd->{dbh}->{dbh}->trace(1);

ok $cd->page(1,2)->read(), 'paging no fail page 1';
#warn to_dumper [$cd->hashes];

ok $cd->page(2,2)->read(), 'paging no fail page 2';
#warn to_dumper [$cd->hashes];

ok $cd->page(3,2)->read(), 'paging no fail page 3';
#warn to_dumper [$cd->hashes];