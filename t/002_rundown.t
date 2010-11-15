use strict;
use warnings;
use Test::More tests => 56, import => ['!pass'];
use Test::Exception;
use FindBin;

BEGIN {
    use_ok 'ORMesque';
}

eval { require DBD::SQLite };
if ($@) {
    plan skip_all => 'DBD::SQLite is required to run these tests';
}

diag 'basic operations';

my $db = ORMesque->new('dbi:SQLite:' . "$FindBin::Bin/000_database.db");
my $user = $db->user;
ok $db, 'database connection established';
ok $user, 'user table object exists';
ok $user->delete_all, 'removed any existing data from user table';
ok !$user->count, 'no users exist yet';
ok $user->name('Bob'), 'new user name set';
ok $user->age(20), 'new user age set';
eval {ok $user->gender('M'), 'new user gender set'};
ok $@, 'error in attempting to set non-existent column';
ok !$user->count, 'no users exist yet after setting columns';
ok $user->create($user->current), 'user insert wo/error';
ok !$user->count, 'current collection count still zero after insert';
ok $user->read->count eq 1, '1 user now exists in the users table';
ok $user->count eq 1, 'count object reports the correct value';
ok $user->name eq 'Bob', 'users name is Bob';
ok $user->age == 20, 'users age is 20';
ok !$user->next, 'next 0 because there is no more users in the collection';
ok $user->name('Bob 2.0'), 'change name of the first user in the resultset';
ok $user->create($user->current), 'first user cloned, basically';
ok $user->read->count eq 2, 'user cloned successfully';
ok $user->update($user->current, $user->name), 'user update command succesfully';
ok $user->age(45), 'change current users age';
ok $user->update($user->current, $user->name), 'users age updated succesfully';
ok $user->read->count eq 2, 'user records in-tact';
ok $user->age eq 45, 'users new age reflected';
ok $user->delete($user->name), 'Bob deleted';
ok $user->read->count eq 1, 'only 1 Bob left';
ok $user->name eq 'Bob 2.0', 'its all left up to Bob 2.0';
ok $user->name('Bob'), 'new Bob';
ok $user->create($user->current), 'made a new Bob';
ok $user->delete({ name => { like => 'Bob%' } }), 'deleted all Bob look alikes';
ok !$user->read->count, 'no more Bobs';

diag 'the 3 Bobs';

ok $user->name('Bob'), 'yo bob';
ok $user->age(20), 'you 20';
ok $user->create($user->current), 'go ahead in bob';
ok $user->name('Bobbie'), 'aye .. bobbay';
ok $user->age(30), 'what the deal';
ok $user->create($user->current), 'you cool, you in bobbie';
ok $user->name('Bobbo'), 'my main man';
ok $user->age(25), 'hows it hangin';
ok $user->create($user->current), 'bobbo, .., the bobster';
ok $user->read, 'are all Bobs present';
ok $user->last, 'Bobbo, gimme five';
ok $user->name eq 'Bobbo', 'Hi';
ok $user->first, 'Bob, gimme five';
ok $user->name eq 'Bob', 'No thanks douche';
ok $user->delete($user->name), 'Cya Bob, fuckoff';
ok $user->last, 'and as for you...';
ok $user->delete($user->name), 'Bobbo, go pound sand';
ok $user->read->count eq 1, 'And then there was one';
ok $user->first, 'you are the first';
ok $user->last, 'and the last';

diag 'functions tests';

ok $user->clear, 'cleaned house';
ok $user->name('Johnny'), 'preparing the new person';
ok !$user->age(undef), 'he hasnt been born yet';
ok $user->create($user->current), 'he was just inserted :)';
ok $user->return, 'he was born successfully';


# warn to_dumper $user->return;