use HexChat qw(:all);

use strict;
use warnings "all";
use Socket; # hexchat in windows does not ship proper memcache interface, so we will
            # use Socket module and memcache text protocol
use Digest::MD5 qw(md5_base64);

sub hookfn;
sub loadliststatus($);
sub loadlist($);
sub savelist(@);
sub savesetting(@);
sub freehooks;

my $script_name = "URL_Memcacher";
HexChat::register($script_name, '0.3', 'Automatically stores URLs to Memcache', \&freehooks);

HexChat::print("$script_name loaded\n");
my $help = 'Usage:
/dl enable nick|domain <name>  - enable nick or domain blacklist
/dl disable nick|domain <name> - disable nick or domain blacklist
/dl add nick|domain <name>     - adds nick or domain to apropriate blacklist
/dl del nick|domain <name>     - removes nick or domain from apropriate blacklist
/dl show                       - show blacklists
/dl info                       - same as above
';
my @hooks;
push @hooks, HexChat::hook_print('Channel Message', \&hookfn);
push @hooks, HexChat::hook_print('Channel Msg Hilight', \&hookfn);
push @hooks, HexChat::hook_print('Channel Action', \&hookfn);
push @hooks, HexChat::hook_print('Channel Action Hilight', \&hookfn);
push @hooks, HexChat::hook_command('dl', \&dl_cmd);

my $host="localhost";
my $port="11211";


sub hookfn {
	my ($nick, $text, $modechar) = @{$_[0]};
	my $nicklist = loadliststatus('dl_nicklist');

	if ($nicklist != 0) {
		my @nicklist = loadlist('dl_nicks');

		foreach (@nicklist) {
			next unless(defined($_));
			next if($_ eq '');

			if ($_ eq $nick) {
				undef $nick; undef $text; undef $modechar;
				undef $nicklist;
				@nicklist = -1; undef @nicklist;
				return HexChat::EAT_NONE;
			}
		}

		@nicklist = -1; undef @nicklist;
	}

	undef $nicklist;

	my @words = split(/\s+/, $text);

	foreach (@words) {
		my $str = $_;
		next unless(substr($str, 0, 4) eq 'http');

		if ($str =~ m{https?://([a-zA-Z0-9.-]+\.[a-zA-Z]+)/(?:.*)}) {
			my $domain = $1;
			my $domainlist = loadliststatus('dl_domainlist');

			if ($domainlist != 0) {
				my @domainlist = loadlist('dl_domains');

				foreach (@domainlist) {
					next unless(defined($_));
					next if($_ eq '');

					if ($_ eq $domain) {
						undef $nick; undef $text; undef $modechar;
						@words = -1; undef @words;
						undef $str; undef $domain;
						undef $domainlist;
						@domainlist = -1; undef @domainlist;
						return HexChat::EAT_NONE;
					}
				}

				@domainlist = -1, undef @domainlist;
			}

			undef $domainlist;

			if (socket(SOCK, PF_INET, SOCK_STREAM, getprotobyname('tcp'))) {
				my $iaddr = inet_aton($host);
				my $paddr = sockaddr_in($port, $iaddr);
				
				if (connect(SOCK, $paddr)) {
					send (SOCK, sprintf("set %s 0 0 %s noreply\r\n%s\r\nquit\r\n", md5_base64($str), length($str), $str), 0);
				}

				close(SOCK);
				undef $iaddr; undef $paddr;
			}
		}
	}

	@words = -1; undef @words;
	undef $nick; undef $text; undef $modechar;

	return HexChat::EAT_NONE;
}

sub loadliststatus($) {
	my $listtype = shift;
	my $list = HexChat::plugin_pref_get($listtype);

	unless (defined($list)) {
		savesetting('list', '0');
		$list = 0;
	}

	undef $listtype;
	return $list;
}

sub loadlist($) {
	my $setting = shift;
	my $val = HexChat::plugin_pref_get($setting);

	unless (defined($val)) {
		savesetting($setting, encode_base64('', ''));
		$val = '';
	}

	my @values = map { decode_base64($_); } split(/ /, $val);
	undef $setting; undef $val;
	return @values;
}

sub savelist(@) {
	my $setting = shift;
	my @list = map { encode_base64($_, ''); } @_;
	my $value = join(' ', @list);
	@list = -1; undef @list;
	return savesetting($setting, $value);
}

sub savesetting(@) {
	my $setting = shift;
	my $value = shift;

	if (HexChat::plugin_pref_set($setting, $value) == 0) {
		HexChat::printf("Unable to save settings for %s\n", $script_name);
		undef $setting; undef $value;
		return undef;
	}

	undef $setting;
	return 1;
}

sub dl_cmd {
	shift(@{$_[0]});
	my $cmd = shift(@{$_[0]});
	my $entity = shift(@{$_[0]});
	my $value = join(' ', @{$_[0]});
	HexChat::print("\n");
	my $msg = undef;

	if (defined($cmd)) {
		if ($cmd eq 'enable') {
			if($entity eq 'nick') {
				if (defined(savesetting('dl_nicklist', '1'))) {
					$msg = "Nicks blacklist now enabled\n";
				}
			} elsif ($entity eq 'domain') {
				if (defined(savesetting('dl_domainlist', '1'))) {
					$msg = "Domains blacklist now enabled\n";
				}
			}
		} elsif ($cmd eq 'disable') {
			if($entity eq 'nick') {
				if (defined(savesetting('dl_nicklist', '0'))) {
					$msg = "Nicks blacklist now disabled\n";
				}
			} elsif ($entity eq 'domain') {
				if (defined(savesetting('dl_domainlist', '0'))) {
					$msg = "Domains blacklist now disabled\n";
				}
			}
		} elsif (($cmd eq 'show') or ($cmd eq 'info')) {
			$msg = '';

			if (loadliststatus('dl_nicklist') == 0) {
				$msg .= "Nicks blacklist:    disabled\n";
			} else {
				$msg .= "Nicks blacklist:    enabled\n";
			}

			$msg .= "Blacklisted nicks = " . join( ', ', loadlist('dl_nicks')) ."\n";

			if (loadliststatus('dl_domainlist') == 0) {
				$msg .= "Domains blacklist:  disabled\n";
			} else {
				$msg .= "Domains blacklist:  enabled\n";
			}

			$msg .= "Blacklisted domains = " . join( ', ', loadlist('dl_domains')) . "\n";
		} elsif ($cmd eq 'add') {
			if ((defined($entity)) and (defined($value))) {
				if ($entity eq 'nick') {
					my @nicks = (loadlist('dl_nicks'), $value);

					unless (defined(savelist('dl_nicks', @nicks))) {
						undef $cmd; undef $entity; undef $value; undef $msg;
						@nicks = -1; undef @nicks;
						return HexChat::EAT_ALL;
					}

					$msg = sprintf("Nicks blacklist now: %s\n", join(', ', @nicks));
					@nicks = -1; undef @nicks;
				} elsif ($entity eq 'domain') {
					my @domains = (loadlist('dl_domains'), $value);

					unless (defined(savelist('dl_domains', @domains))) {
						undef $cmd; undef $entity; undef $value; undef $msg;
						@domains = -1; undef @domains;
						return HexChat::EAT_ALL;
					}

					$msg = sprintf("Domains blacklist now: %s\n", join(', ', @domains));
					@domains = -1; undef @domains;
				}
			}
		} elsif ($cmd eq 'del') {
			if ((defined($entity)) and (defined($value))) {
				if ($entity eq 'nick') {
					my @list = loadlist('dl_nicks');
					my @nicklist;

					foreach (@list) {
						next if ($_ eq $value);
						push @nicklist, $_;
					}

					@list = -1; undef @list;

					unless (defined(savelist('dl_nicks', @nicklist))) {
						undef $cmd; undef $entity; undef $value; undef $msg;
						@nicklist = -1; undef @nicklist;
						return HexChat::EAT_ALL;
					}

					$msg = sprintf("Nicks blacklist now: %s\n", join(', ', @nicklist));
					@nicklist = -1; undef @nicklist;
				} elsif ($entity eq 'domain') {
					my @list = loadlist('dl_domains');
					my @domainlist;

					foreach (@list) {
						next if ($_ eq $value);
						push @domainlist, $_;
					}

					@list = -1; undef @list;

					unless (defined(savelist('dl_domains', @domainlist))) {
						undef $cmd; undef $entity; undef $value; undef $msg;
						@domainlist = -1; undef @domainlist;
						return HexChat::EAT_ALL;
					}

					$msg = sprintf("Domains blacklist now: %s\n", join(', ', @domainlist));
					@domainlist = -1; undef @domainlist;
				}
			}
		}
	}

	unless(defined($msg)) {
		HexChat::print($help);
	} else {
		HexChat::print($msg);
	}

	undef $cmd; undef $entity; undef $value; undef $msg;
	return HexChat::EAT_ALL;
}

sub freehooks {
	foreach (@hooks) {
		HexChat::unhook($_);
	}

	return HexChat::EAT_ALL;
}
