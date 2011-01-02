    use 5.006;
    use strict;
    use DBI;
    use Carp ();
    
    $DBIx::Simple::VERSION = '1.32_MOD';
    $Carp::Internal{$_} = 1
	for qw(DBIx::Simple DBIx::Simple::Result DBIx::Simple::DeadObject);
    
    my $quoted         = qr/(?:'[^']*'|"[^"]*")*/;  # 'foo''bar' simply matches the (?:) twice
    my $quoted_mysql   = qr/(?:(?:[^\\']*(?:\\.[^\\']*)*)'|"(?:[^\\"]*(?:\\.[^\\"]*)*)")*/;
    
    my %statements;       # "$db" => { "$st" => $st, ... }
    my %old_statements;   # "$db" => [ [ $query, $st ], ... ]
    my %keep_statements;  # "$db" => $int
    
    my $err_message = '%s no longer usable (because of %%s)';
    my $err_cause   = '%s at %s line %d';
    
    package #Hide from PAUSE
	DBIx::Simple;
    
    ### private helper subs
    
    sub _dummy { bless \my $dummy, 'DBIx::Simple::Dummy' }
    sub _swap {
	my ($hash1, $hash2) = @_;
	my $tempref = ref $hash1;
	my $temphash = { %$hash1 };
	%$hash1 = %$hash2;
	bless $hash1, ref $hash2;
	%$hash2 = %$temphash;
	bless $hash2, $tempref;
    }
    
    ### constructor
    
    sub connect {
	my ($class, @arguments) = @_;
	my $self = { lc_columns => 1, result_class => 'DBIx::Simple::Result' };
	if (defined $arguments[0] and UNIVERSAL::isa($arguments[0], 'DBI::db')) {
	    $self->{dont_disconnect} = 1;
	    $self->{dbh} = shift @arguments;
	    Carp::carp("Additional arguments for $class->connect are ignored")
		if @arguments;
	} else {
	    $arguments[3]->{PrintError} = 0
		unless defined $arguments[3] and defined $arguments[3]{PrintError};
	    $self->{dbh} = DBI->connect(@arguments);
	}
    
	return undef unless $self->{dbh};
    
	$self->{dbd} = $self->{dbh}->{Driver}->{Name};
	bless $self, $class;
    
	$statements{$self}      = {};
	$old_statements{$self}  = [];
	$keep_statements{$self} = 16;
    
	return $self;
    }
    
    sub new {
	my ($class) = shift;
	$class->connect(@_);
    }
    
    ### properties
    
    sub keep_statements : lvalue { $keep_statements{ $_[0] } }
    sub lc_columns      : lvalue { $_[0]->{lc_columns} }
    sub result_class    : lvalue { $_[0]->{result_class} }
    
    sub abstract : lvalue {
	require SQL::Abstract::Limit;
	$_[0]->{abstract}
	||= SQL::Abstract::Limit->new( limit_dialect => $_[0]->{dbh} );
    }
    
    ### private methods
    
    # Replace (??) with (?, ?, ?, ...)
    sub _replace_omniholder {
	my ($self, $query, $binds) = @_;
	return if $$query !~ /\(\?\?\)/;
	my $omniholders = 0;
	my $q = $self->{dbd} =~ /mysql/ ? $quoted_mysql : $quoted;
	$$query =~ s[($q|\(\?\?\))] {
	    $1 eq '(??)'
	    ? do {
		Carp::croak('There can be only one omniholder')
		    if $omniholders++;
		'(' . join(', ', ('?') x @$binds) . ')'
	    }
	    : $1
	}eg;
    }
    
    # Invalidate and clean up
    sub _die {
	my ($self, $cause) = @_;
    
	defined and $_->_die($cause, 0)
	    for values %{ $statements{$self} },
	    map $$_[1], @{ $old_statements{$self} };
	delete $statements{$self};
	delete $old_statements{$self};
	delete $keep_statements{$self};
    
	unless ($self->{dont_disconnect}) {
	    # Conditional, because destruction order is not guaranteed
	    # during global destruction.
	    # $self->{dbh}->disconnect() if defined $self->{dbh};
	    
	    # this thing seem to be breaking lots of shit and I don't know why,
	    # also I'd argue whether its even neccessary :\ so im commenting it out
	    # eval { $self->{dbh}->disconnect() if defined $self->{dbh} };
	}
    
	_swap(
	    $self,
	    bless {
		what  => 'Database object',
		cause => $cause
	    }, 'DBIx::Simple::DeadObject'
	) unless $cause =~ /DESTROY/;  # Let's not cause infinite loops :)
    }
    
    ### public methods
    
    sub query {
	my ($self, $query, @binds) = @_;
	$self->{success} = 0;
    
	$self->_replace_omniholder(\$query, \@binds);
    
	my $st;
	my $sth;
    
	my $old = $old_statements{$self};
    
	if (my $i = (grep $old->[$_][0] eq $query, 0..$#$old)[0]) {
	    $st = splice(@$old, $i, 1)->[1];
	    $sth = $st->{sth};
	} else {
	    eval { $sth = $self->{dbh}->prepare($query) } or do {
		if ($@) {
		    $@ =~ s/ at \S+ line \d+\.\n\z//;
		    Carp::croak($@);
		}
		$self->{reason} = "Prepare failed ($DBI::errstr)";
		return _dummy;
	    };
    
	    # $self is quoted on purpose, to pass along the stringified version,
	    # and avoid increasing reference count.
	    $st = bless {
		db    => "$self",
		sth   => $sth,
		query => $query
	    }, 'DBIx::Simple::Statement';
	    $statements{$self}{$st} = $st;
	}
    
	eval { $sth->execute(@binds) } or do {
	    if ($@) {
		$@ =~ s/ at \S+ line \d+\.\n\z//;
		Carp::croak($@);
	    }
    
	    $self->{reason} = "Execute failed ($DBI::errstr)";
	    return _dummy;
	};
    
	$self->{success} = 1;
    
	return bless { st => $st, lc_columns => $self->{lc_columns} }, $self->{result_class};
    }
    
    sub error {
	my ($self) = @_;
	return 'DBI error: ' . (ref $self ? $self->{dbh}->errstr : $DBI::errstr);
    }
    
    sub dbh            { $_[0]->{dbh}             }
    sub begin_work     { $_[0]->{dbh}->begin_work }
    sub begin          { $_[0]->begin_work        }
    sub commit         { $_[0]->{dbh}->commit     }
    sub rollback       { $_[0]->{dbh}->rollback   }
    sub func           { shift->{dbh}->func(@_)   }
    
    sub last_insert_id {
	my ($self) = @_;
    
	($self->{dbi_version} ||= DBI->VERSION) >= 1.38 or Carp::croak(
	    "DBI v1.38 required for last_insert_id" .
	    "--this is only $self->{dbi_version}, stopped"
	);
    
	return shift->{dbh}->last_insert_id(@_);
    }
    
    sub disconnect {
	my ($self) = @_;
	$self->_die(sprintf($err_cause, "$self->disconnect", (caller)[1, 2]));
    }
    
    sub DESTROY {
	my ($self) = @_;
	$self->_die(sprintf($err_cause, "$self->DESTROY", (caller)[1, 2]));
    }
    
    ### public methods wrapping SQL::Abstract
    
    for my $method (qw/select insert update delete/) {
	no strict 'refs';
	*$method = sub {
	    my $self = shift;
	    return $self->query($self->abstract->$method(@_));
	}
    }
    
    ### public method wrapping SQL::Interp
    
    sub iquery {
	require SQL::Interp;
	my $self = shift;
	return $self->query( SQL::Interp::sql_interp(@_) );
    }
    
    package #nope
	DBIx::Simple::Dummy;
    
    use overload
	'""' => sub { shift },
	bool => sub { 0 };
    
    sub new      { bless \my $dummy, shift }
    sub AUTOLOAD { return }
    
    package #nope
	DBIx::Simple::DeadObject;
    
    sub _die {
	my ($self) = @_;
	Carp::croak(
	    sprintf(
		"(This should NEVER happen!) " .
		sprintf($err_message, $self->{what}),
		$self->{cause}
	    )
	);
    }
    
    sub AUTOLOAD {
	my ($self) = @_;
	Carp::croak(
	    sprintf(
		sprintf($err_message, $self->{what}),
		$self->{cause}
	    )
	);
    }
    sub DESTROY { }
    
    package #nope
	DBIx::Simple::Statement;
    
    sub _die {
	my ($self, $cause, $save) = @_;
    
	$self->{sth}->finish() if defined $self->{sth};
	$self->{dead} = 1;
    
	my $stringy_db = "$self->{db}";
	my $stringy_self = "$self";
    
	my $foo = bless {
	    what  => 'Statement object',
	    cause => $cause
	}, 'DBIx::Simple::DeadObject';
    
	DBIx::Simple::_swap($self, $foo);
    
	my $old = $old_statements{ $foo->{db} };
	my $keep = $keep_statements{ $foo->{db} };
    
	if ($save and $keep) {
	    $foo->{dead} = 0;
	    shift @$old until @$old + 1 <= $keep;
	    push @$old, [ $foo->{query}, $foo ];
	}
    
	delete $statements{ $stringy_db }{ $stringy_self };
    }
    
    sub DESTROY {
	# This better only happen during global destruction...
	return if $_[0]->{dead};
	$_[0]->_die('Ehm', 0);
    }
    
    package #nope
	DBIx::Simple::Result;
    
    sub _die {
	my ($self, $cause) = @_;
	if ($cause) {
	    $self->{st}->_die($cause, 1);
	    DBIx::Simple::_swap(
		$self,
		bless {
		    what  => 'Result object',
		    cause => $cause,
		}, 'DBIx::Simple::DeadObject'
	    );
	} else {
	    $cause = $self->{st}->{cause};
	    DBIx::Simple::_swap(
		$self,
		bless {
		    what  => 'Result object',
		    cause => $cause
		}, 'DBIx::Simple::DeadObject'
	    );
	    Carp::croak(
		sprintf(
		    sprintf($err_message, $self->{what}),
		    $cause
		)
	    );
	}
    }
    
    sub func { shift->{st}->{sth}->func(@_) }
    sub attr { my $dummy = $_[0]->{st}->{sth}->{$_[1]} }
    
    sub columns {
	$_[0]->_die if ref $_[0]->{st} eq 'DBIx::Simple::DeadObject';
	my $c = $_[0]->{st}->{sth}->{ $_[0]->{lc_columns} ? 'NAME_lc' : 'NAME' };
	return wantarray ? @$c : $c;
    }
    
    sub bind {
	$_[0]->_die if ref $_[0]->{st} eq 'DBIx::Simple::DeadObject';
	$_[0]->{st}->{sth}->bind_columns(\@_[1..$#_]);
    }
    
    sub fetch {
	$_[0]->_die if ref $_[0]->{st} eq 'DBIx::Simple::DeadObject';
	return $_[0]->{st}->{sth}->fetch;
    }
    
    sub into {
	$_[0]->_die if ref $_[0]->{st} eq 'DBIx::Simple::DeadObject';
	my $sth = $_[0]->{st}->{sth};
	$sth->bind_columns(\@_[1..$#_]) if @_ > 1;
	return $sth->fetch;
    }
    
    sub list {
	$_[0]->_die if ref $_[0]->{st} eq 'DBIx::Simple::DeadObject';
	return $_[0]->{st}->{sth}->fetchrow_array if wantarray;
	return($_[0]->{st}->{sth}->fetchrow_array)[-1];
    }
    
    sub array {
	$_[0]->_die if ref $_[0]->{st} eq 'DBIx::Simple::DeadObject';
	my $row = $_[0]->{st}->{sth}->fetchrow_arrayref or return;
	return [ @$row ];
    }
    
    sub hash {
	$_[0]->_die if ref $_[0]->{st} eq 'DBIx::Simple::DeadObject';
	return $_[0]->{st}->{sth}->fetchrow_hashref(
	    $_[0]->{lc_columns} ? 'NAME_lc' : 'NAME'
	);
    }
    
    sub flat {
	$_[0]->_die if ref $_[0]->{st} eq 'DBIx::Simple::DeadObject';
	return   map @$_, $_[0]->arrays if wantarray;
	return [ map @$_, $_[0]->arrays ];
    }
    
    sub arrays {
	$_[0]->_die if ref $_[0]->{st} eq 'DBIx::Simple::DeadObject';
	return @{ $_[0]->{st}->{sth}->fetchall_arrayref } if wantarray;
	return    $_[0]->{st}->{sth}->fetchall_arrayref;
    }
    
    sub hashes {
	$_[0]->_die if ref $_[0]->{st} eq 'DBIx::Simple::DeadObject';
	my ($self) = @_;
	my @return;
	my $dummy;
	push @return, $dummy while $dummy = $self->hash;
	return wantarray ? @return : \@return;
    }
    
    sub map_hashes {
	$_[0]->_die if ref $_[0]->{st} eq 'DBIx::Simple::DeadObject';
	my ($self, $keyname) = @_;
	Carp::croak('Key column name not optional') if not defined $keyname;
	my @rows = $self->hashes;
	my @keys;
	push @keys, delete $_->{$keyname} for @rows;
	my %return;
	@return{@keys} = @rows;
	return wantarray ? %return : \%return;
    }
    
    sub map_arrays {
	$_[0]->_die if ref $_[0]->{st} eq 'DBIx::Simple::DeadObject';
	my ($self, $keyindex) = @_;
	$keyindex += 0;
	my @rows = $self->arrays;
	my @keys;
	push @keys, splice @$_, $keyindex, 1 for @rows;
	my %return;
	@return{@keys} = @rows;
	return wantarray ? %return : \%return;
    }
    
    sub map {
	$_[0]->_die if ref $_[0]->{st} eq 'DBIx::Simple::DeadObject';
	return   map @$_, @{ $_[0]->{st}->{sth}->fetchall_arrayref } if wantarray;
	return { map @$_, @{ $_[0]->{st}->{sth}->fetchall_arrayref } };
    }
    
    sub rows {
	$_[0]->_die if ref $_[0]->{st} eq 'DBIx::Simple::DeadObject';
	$_[0]->{st}->{sth}->rows;
    }
    
    sub xto {
	$_[0]->_die if ref $_[0]->{st} eq 'DBIx::Simple::DeadObject';
	require DBIx::XHTML_Table;
	my $self = shift;
	my $attr = ref $_[0] ? $_[0] : { @_ };
    
	# Old DBD::SQLite (.29) spits out garbage if done *after* fetching.
	my $columns = $self->{st}->{sth}->{NAME};
    
	return DBIx::XHTML_Table->new(
	    scalar $self->arrays,
	    $columns,
	    $attr
	);
    }
    
    sub html {
	$_[0]->_die if ref $_[0]->{st} eq 'DBIx::Simple::DeadObject';
	my $self = shift;
	my $attr = ref $_[0] ? $_[0] : { @_ };
	return $self->xto($attr)->output($attr);
    }
    
    sub text {
	$_[0]->_die if ref $_[0]->{st} eq 'DBIx::Simple::DeadObject';
	my ($self, $type) = @_;
	my $text_table = defined $type && length $type
	    ? 0
	    : eval { require Text::Table; $type = 'table'; 1 };
	$type ||= 'neat';
	if ($type eq 'box' or $type eq 'table') {
	    my $box = $type eq 'box';
	    $text_table or require Text::Table;
	    my @columns = map +{ title => $_, align_title => 'center' },
		@{ $self->{st}->{sth}->{NAME} };
	    my $c = 0;
	    splice @columns, $_ + $c++, 0, \' | ' for 1 .. $#columns;
	    my $table = Text::Table->new(
		($box ? \'| ' : ()),
		@columns,
		($box ? \' |' : ())
	    );
	    $table->load($self->arrays);
	    my $rule = $table->rule(qw/- +/);
	    return join '',
		($box ? $rule : ()),
		$table->title, $rule, $table->body,
		($box ? $rule : ());
	}
	Carp::carp("Unknown type '$type'; using 'neat'") if $type ne 'neat';
	return join '', map DBI::neat_list($_) . "\n", $self->arrays;
    }
    
    sub finish {
	$_[0]->_die if ref $_[0]->{st} eq 'DBIx::Simple::DeadObject';
	my ($self) = @_;
	$self->_die(
	    sprintf($err_cause, "$self->finish", (caller)[1, 2])
	);
    }
    
    sub DESTROY {
	return if ref $_[0]->{st} eq 'DBIx::Simple::DeadObject';
	my ($self) = @_;
	$self->_die(
	    sprintf($err_cause, "$self->DESTROY", (caller)[1, 2])
	);
    }

    package #Hide from PAUSE
	ORMesque::DBIxSimpleHack;
1;