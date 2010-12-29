use strict;
use warnings;
use Test::More import => ['!pass'];
use Test::Exception;
use FindBin;

BEGIN {
    use_ok 'ORMesque';
}

eval { require DBD::SQLite };
if ($@) {
    plan skip_all => 'DBD::SQLite is required to run these tests';
}
else {
    plan tests => 13;
}

my $db = ORMesque->new('dbi:SQLite:' . "$FindBin::Bin/001_database.db");

diag 'testing objects';

ok $db, 'database object received';
ok $db->cd, 'cd table object exists';
ok $db->artist, 'artist table object exists';
ok $db->playlist, 'playlist table object exists';
ok $db->track, 'track table object exists';
ok $db->playlist_track, 'playlist_track table object exists';

diag 'delete everything';

ok $db->cd->delete_all, 'removed any existing data from cd table';
ok $db->artist->delete_all, 'removed any existing data from artist table';
ok $db->playlist->delete_all, 'removed any existing data from playlist table';
ok $db->track->delete_all, 'removed any existing data from track table';
ok $db->playlist_track->delete_all, 'removed any existing data from playlist_track table';

diag 'setup database data';

my  (
        $cd,
        $artist,
        $playlist,
        $track,
        $playlist_track
    )
        =
    (
        $db->cd,
        $db->artist,
        $db->playlist,
        $db->track,
        $db->playlist_track
    );

$artist->create({ name => 'Micheal Jackson' })->return;
$cd->create({ artist => $artist->id(), name => $_ })

    for (
        'Invincible',
        'Blood On The Dance Floor',
        'HIStory',
        'Dangerous',
        'Bad',
        'Thriller',
        'Off The Wall'
    );

$cd->read({ artist => $artist->id() });
$artist->read({ id => $artist->id() });

my $resultset = {};

eval{ $resultset = $cd->join() };
ok $@, 'join requires two or more ORMesque objects';

#$db->{dbh}->{dbh}->trace(1);
#$cd->read;
#warn to_dumper [$cd->list];

#$resultset = $cd->join({ columns => { cd_name => 'cd' } }, $artist, { persist => 1, columns => { artist_name => 'artist' } });
#warn to_dumper $resultset;

#$resultset = $cd->join({ columns => { cd_name => 'cd' } }, $artist, { persist => 1, columns => { artist_name => 'artist' } });
#warn to_dumper $resultset;