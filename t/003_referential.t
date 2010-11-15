use strict;
use warnings;
use Test::More tests => 16, import => ['!pass'];
use Test::Exception;
use FindBin;

BEGIN {
    use_ok 'ORMesque';
}

eval { require DBD::SQLite };
if ($@) {
    plan skip_all => 'DBD::SQLite is required to run these tests';
}

diag 'testing objects';

my $db = ORMesque->new('dbi:SQLite:' . "$FindBin::Bin/001_database.db");
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

my $artist_count = $artist->read->count();
my $cd_count     = $cd->read({ artist => $artist->id() })->count();

ok 1 == $artist_count, '1 artist';
ok 7 == $cd_count, '7 albums';

diag 'test select specific columns';

ok $cd->select('name'), 'select specific column syntax';
$cd->read; my $value = 0; for (values %{ $cd->current }) { $value++ if $_; }
ok $value == 1, 'select specific column works';

# warn to_dumper $user->return;