#!/usr/bin/perl


use constant {
	VERSION => '0.1b2',
	DEFAULT_CHANGE_LOG_FILE => '/var/log/changes'
};

# line length in characters
use constant LINE_LENGTH => 71;

# lines separating entries from each other
use constant {
	ENTRY_SEPARATOR => '-' x LINE_LENGTH,
	HEADER_SEPARATOR => '=' x LINE_LENGTH
};

# tag sizes
use constant {
	TAB_SIZE => 8,		# number of spaces that a tab character occupies
	DATE_SIZE => 10,	# length of the date string in characters
	USER_SIZE => 7		# length of user name in characters
};

use constant {
	# number of tabs neccessary to go over date string
	DATE_TABS => int(DATE_SIZE / TAB_SIZE + 1),
	# number of tabs neccessary to go over user string
	USER_TABS => int(USER_SIZE / TAB_SIZE + 1)
};

# number of chracters left for log entry text
use constant COLUMN_SIZE => LINE_LENGTH - TAB_SIZE * (DATE_TABS + USER_TABS);

#use Data::Dumper;			# debug
use Fcntl qw(:flock);			# import constants for file locking
use feature qw(say);			# use 5.10 "say" feature
use Getopt::Std;			# arg parsing with C-style getopts()
use locale;				# use current system locale
use open ':encoding(utf8)';		# set file I/O encoding to UTF-8
use POSIX qw(locale_h strftime);
use strict;




# set STDIN/STDOUT/ARGV encoding to UTF-8 if utf8 locale in use
my ($lc_col, $lc_ctype) = (setlocale(LC_COLLATE), setlocale(LC_CTYPE));
if ($lc_ctype =~ /utf-?8/i) {
	binmode(STDIN, ":encoding(utf8)");
	binmode(STDOUT, ":encoding(utf8)");
	Encode::_utf8_on($_) for (@ARGV);
}


### arguments parsing ##########################################################

# getopts shall exit after printing --help or --version message
$Getopt::Std::STANDARD_HELP_VERSION = 1;

my %arg_opts;

# get arguments, see --help for description
getopts('Vh?vse:r:u:d:f:', \%arg_opts);

if (defined($arg_opts{'h'}) || defined($arg_opts{'?'})) {
	VERSION_MESSAGE();
	HELP_MESSAGE();
	exit();
}

if (defined($arg_opts{'V'})) {
	VERSION_MESSAGE();
	exit();
}

# save options
my %options = (
	'verbose'		=> (defined($arg_opts{'v'}) ? 1 : 0),
        'show_log'		=> (defined($arg_opts{'s'}) ? 1 : 0),
	'reboot'		=> (defined($arg_opts{'r'}) ? 1 : 0),
        'etc_commit'		=> (defined($arg_opts{'e'}) ? 1 : 0),
        'etc_commit_msg'	=> (defined($arg_opts{'e'}) ? $arg_opts{'e'} : ''),
	'change_log_file'	=> (defined($arg_opts{'f'}) ? $arg_opts{'f'} : DEFAULT_CHANGE_LOG_FILE)
);




### main #######################################################################

# some verbose output
if ($options{'verbose'}) {
	VERSION_MESSAGE();
	if ($lc_col eq $lc_ctype) {
		say 'Using locale ', $lc_col;
	} else {
		say 'Using locales LC_CTYPE=', $lc_ctype, ', LC_COLLATE=', $lc_col;
	}
	say 'Tab size is ', TAB_SIZE;
	say 'Reading file ', $options{'change_log_file'};
}


# try opening the change log file
open(LOG, '+<'.$options{'change_log_file'}) or die "Opening change log failed: $!\n";
unless (flock(LOG, LOCK_EX | LOCK_NB)) {
	warn "File already locked, waiting ...\n";
	flock(LOG, LOCK_EX) or die "Could not lock change log: $!\n";
}

# read file into memory
my @old_changes = <LOG>;

# backup
if (open(LOGCPY, ">$options{'change_log_file'}~")) {
	print LOGCPY @old_changes;
	close(LOGCPY);
	say 'Backup saved to ', $options{'change_log_file'}, '~' if ($options{'verbose'});
} else {
	warn "Backup skipped, opening backup file failed: $!\n";
}

# remove trailing newline chars
chomp @old_changes;

# preserve header
my @header;
shift(@old_changes) if ($old_changes[0] eq HEADER_SEPARATOR);
while (@old_changes && (($_ = shift(@old_changes)) ne HEADER_SEPARATOR)
	&& ($_ ne ENTRY_SEPARATOR)) {
	push(@header, $_);
}
	
# parse entries into hash referenced by $log_entries
my $log_entries;

my $date_tabs = DATE_TABS - 1; # need that for the regex
my $user_tabs = USER_TABS - 1; # need that for the regex

while (@old_changes) {
	#print "foo"; # debug
	
	my ($last_entry_date, $last_entry_user);
	
	while (@old_changes && (($_ = shift(@old_changes)) ne ENTRY_SEPARATOR)) {
		#print "bar"; # debug
		
		# try pattern matching a line, croak on failure
		parse_error($_) unless
			(my ($entry_date, $entry_user, $new_line, $entry_line) = 
				($_ =~ /^(?:(?:(\d{4}-\d{2}-\d{2})|\t{$date_tabs})\t(?:(\w+)|\t{$user_tabs})\s+|\s*)(- )?(.*?)\s*$/o));
				
		# remember last date and user for entry clustering
		$last_entry_date = substr($entry_date, 0, DATE_SIZE)
			if (defined($entry_date) && $entry_date ne '');
		$last_entry_user = substr($entry_user, 0, USER_SIZE)
			if (defined($entry_user) && $entry_user ne '');
		
		#say $last_entry_date, ':', $entry_date; # debug
		#say $last_entry_user, ':', $entry_user; # debug
		
		# if there isn't any entry yet for the date and user (value is undefined)
		# then we create an empty array for that key so we can use a shortcut
		@{$log_entries->{$last_entry_date}->{$last_entry_user}} = ()
			if (!defined($log_entries->{$last_entry_date}->{$last_entry_user}));
		
		# shortcut
		my $a = $log_entries->{$last_entry_date}->{$last_entry_user};
		
		# if the entry line starts with "- " then it's a new entry, not the
		# continuation of the previous line.
		# if it doesn't start with "- " but there is no previous line
		# (i.e. someone forgot to put the "- " in front) then it's a new
		# entry, too
		if (defined($new_line) || !@{$a}) {
			# add new element to the list of entries for that date/user key
			push(@{$a}, $entry_line);
		} else {
			# concatenate with previous line
			# don't add space if hyphenated line
			@{$a}[-1] .= ' ' unless (substr(@{$a}[-1], -1) eq '-');
			@{$a}[-1] .= $entry_line;
		}
	}
}

# D'oh!
die "Parse error: unrecognized format.\n" unless defined($log_entries);

#print Dumper($log_entries); # debug

# set username for new entry
my $user = defined($arg_opts{'u'})	?
	$arg_opts{'u'} :
	getlogin() || getpwuid($<) || '<?>';
$user = substr($user, 0, USER_SIZE);
say 'User: ', $user if ($options{'verbose'});

# set date for new entry
my $date;
if (defined($arg_opts{'d'})) {
	die "$arg_opts{'d'} is not a valid date format\n"
		if ($arg_opts{'d'} !~ /^\d{4}-\d{2}-\d{2}$/);
	$date = $arg_opts{'d'};
} else {
	$date = strftime('%Y-%m-%d', localtime());
}
say 'Date: ', $date if ($options{'verbose'});

# read changes, either from command line or from STDIN
my @changes;
if (@ARGV) {
	$changes[0] = join(' ', @ARGV);
} else {
	say 'Enter changes (CTRL-D to finish):';
	@changes = <STDIN>;
	chomp @changes;
}

# sort out emptyness
map { s/^-\s*//o; } @changes;
@changes = grep(!/^\s*$/, @changes);
die "No changes given, file not modified.\n" unless (@changes);

# add/update new entry
push(@{$log_entries->{$date}->{$user}}, @changes);

# clear change log file
die "Cannot modify file: $!\n" unless truncate(LOG, 0);
seek(LOG, 0, 0);

print "\n";

# write new file
say LOG HEADER_SEPARATOR;
map { say LOG; } @header;
say LOG HEADER_SEPARATOR;

if ($options{'show_log'}) {
	say HEADER_SEPARATOR;
	map { say; } @header;
	say HEADER_SEPARATOR;
}

my $column_size = COLUMN_SIZE - 2; # need to add '- ' (first line) / '  ' (next lines)
my $str;

# sort entries by date
for my $entry_date (sort { uc($a) cmp uc($b) } keys %{$log_entries}) {
	my $date_str = $entry_date;
	# sort usernames per date
	for my $entry_user (sort { uc($a) cmp uc($b) } keys %{$log_entries->{$entry_date}}) {
		my $user_str = $entry_user;
		# for all entries of the user on that date
		for (@{$log_entries->{$entry_date}->{$entry_user}}) {
			# wrap lines to $column_size chars
			$_ =~ s/(.{1,$column_size})(?:\s+|$|(?<=\w)(-))\n?|(.{$column_size})/$1$2$3\n/og;
			my @lines = split(/\n/, $_);
			
			# write first line: DATE	USER	- foobar
			# 				or:			USER	- foobar
			$str = $date_str . "\t" . $user_str . "\t- " . shift(@lines);
			say LOG $str;
			say $str if ($options{'show_log'});
			
			# date and username have been written, replace wth blanks
			$date_str = "\t" x (DATE_TABS - 1);
			$user_str = "\t" x (USER_TABS - 1);
			
			# write rest of the lines
			for (@lines) {
				$str = $date_str . "\t" . $user_str . "\t  " . $_ ;
				say LOG $str;
				say $str if ($options{'show_log'});
			}
		}
	}
	say LOG ENTRY_SEPARATOR;
	say ENTRY_SEPARATOR if ($options{'show_log'});
}

say $options{'change_log_file'}, ' updated.';

# do not unlock file prior to closing it, data might be buffered
close(LOG);

# run etckeeper
if ($options{'etc_commit'}) {
	print 'Running etckeeper ... ' if ($options{'verbose'});
	if (system('etckeeper', 'commit', "\"$options{'etc_commit_msg'}\"") == 0) {
		say 'OK' if ($options{'verbose'});
	} else {
		say 'failed: ', $! if ($options{'verbose'});
	}
}

# reboot
if ($options{'reboot'}) {
	print 'Scheduling reboot ... ' if ($options{'verbose'});
	if (system('shutdown', '-r', '+1', "Reboot initiated by $0") == 0) {
		say 'OK' if ($options{'verbose'});
	} else {
		say 'failed: ', $! if ($options{'verbose'});
	}
}


### subs #######################################################################

sub parse_error {
	die "Parse error at line \"$_[0]\"\nFile not modified.\n";
}


# version screen, called wih --version
sub VERSION_MESSAGE {
	say 'changelog version ', VERSION;
}

# help screen, called wih --help
sub HELP_MESSAGE {
	my $default_change_log_file = DEFAULT_CHANGE_LOG_FILE;
	print <<EOT;

Adds an entry to the change log. Changes can be specified on the command line or on STDIN and will be automatically formated into paragraphs. The script parses and rebuilds the file completely, so if you specify a date and user which already have entries, it will be smart enough to add the changes to them. You can also let etckeeper commit changes to /etc or reboot the machine conveniently after updating the change log file, see options below.
	
Usage: changelog [OPTIONS] [text]

Options:
    --version   Show version.
    --help, -h  Show this help screen.
    -d date     Add entry for date. Format is YYYY-MM-DD. Default: today
    -e message  Commit changes to /etc with etckeeper and given commit message.
    -f file     Use file "file" as change log file. Default: $default_change_log_file
    -r          Reboot the system after updating the change log file.
    -s          Output the log file after processing it.
    -u user     Add entry for user "user". Default: current user
    -v          Verbose output.
    text        Text of the log entry. Will be read from STDIN if not given on
                the command line. Text will be automatically wrapped into
                paragraphs. Use return on STDIN to enter several entries.

EOT
}
