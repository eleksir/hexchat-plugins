use 5.018;
use strict;
use warnings;
use utf8;
use open qw (:std :utf8);
use HTTP::Tiny;
use HexChat qw (:all);

sub hookfn;
sub listenabled ($);
sub loadlist ($);
sub savelist (@);
sub savesetting (@);
sub freehooks;

my $script_name = 'img_url_myapi.pl';
my $script_version = '0.2';
my $script_description = 'Automatically stores URLs to myapi';

register (
	$script_name,
	$script_version,
	$script_description,
	\&freehooks
);

print "$script_name loaded\n";
my $help = << 'HELP';
Usage:
/dl enable nick|domain <name>  - enable nick or domain blacklist
/dl disable nick|domain <name> - disable nick or domain blacklist
/dl add nick|domain <name>     - adds nick or domain to apropriate blacklist
/dl del nick|domain <name>     - removes nick or domain from apropriate blacklist
/dl show                       - show blacklists
/dl info                       - same as above
HELP

my @hooks;
push @hooks, hook_print   ('Channel Message',        \&hookfn);
push @hooks, hook_print   ('Channel Msg Hilight',    \&hookfn);
push @hooks, hook_print   ('Channel Action',         \&hookfn);
push @hooks, hook_print   ('Channel Action Hilight', \&hookfn);
push @hooks, hook_command ('dl',                     \&dl_cmd);


sub hookfn {
	my ($nick, $text, $modechar) = @{$_[0]};

	if (listenabled 'dl_nicklist') {
		my @nicklist = loadlist 'dl_nicks';

		foreach my $nickname (@nicklist) {
			next unless (defined $nickname);
			next if (($nickname eq '') || ($nickname ne $nick));

			$nick = '';      undef $nick;
			$text = '';      undef $text;
			$modechar = '';  undef $modechar;
			$#nicklist = -1; undef @nicklist;
			return EAT_NONE;
		}

		$#nicklist = -1; undef @nicklist;
	}

	my @words = split /\s+/xms, $text;

	foreach my $str (@words) {
		next unless (substr ($str, 0, 4) eq 'http');

# disregard idn, until it cause real troubles :)
		if ($str =~ m{https?://([a-zA-Z0-9\.\-_]+\.[a-zA-Z]+)/(?:.*)}) {
			my $domain = $1;

			if (listenabled 'dl_domainlist') {
				my @domainlist = loadlist 'dl_domains';

				foreach my $dom (@domainlist) {
					next unless (defined $dom);
					next if (($dom eq '') || ($dom ne $domain));

					$nick = '';        undef $nick;
					$text = '';        undef $text;
					$modechar = '';    undef $modechar;
					$#words = -1;      undef @words;
					$str = '';         undef $str;
					$domain = '';      undef $domain;
					$#domainlist = -1; undef @domainlist;
					return EAT_NONE;
				}

				$#domainlist = -1, undef @domainlist;
			}

			my $http2 = HTTP::Tiny->new ('default_headers' => { 'url' => $str });
			$http2->get ('http://localhost/api/image_dl');
			$http2 = ''; undef $http2;
		}
	}

	$#words = -1;   undef @words;
	$nick = '';     undef $nick;
	$text = '';     undef $text;
	$modechar = ''; undef $modechar;

	return EAT_NONE;
}

sub listenabled ($) {
	my $listtype = shift;
	my $list = plugin_pref_get $listtype;
	$listtype = ''; undef $listtype;

	if (defined $list) {
		return $list;
	}

	savesetting 'list', '0';
	return 0;
}

sub loadlist ($) {
	my $setting = shift;
	my $value = plugin_pref_get $setting;

	unless (defined $value) {
		savesetting $setting, encode_base64 ('', '');
		$value = '';
	}

	my @values = map { decode_base64 ($_); } split (/ /, $value);
	$setting = ''; undef $setting;
	$value = ''; undef $value;
	return @values;
}

sub savelist (@) {
	my $setting = shift;
	my @list = map { encode_base64 ($_, ''); } @_;
	my $value = join (' ', @list);
	$#list = -1; undef @list;
	my $res = savesetting $setting, $value;
	$setting = ''; undef $setting;
	$value = ''; undef $value;
	return $res;
}

sub savesetting (@) {
	my $setting = shift;
	my $value = shift;
	my $result = plugin_pref_set $setting, $value;
	$setting = ''; undef $setting;
	$value = ''; undef $value;

	if ($result) {
		return 1;
	}

	printf "Unable to save settings for %s\n", $script_name;
	return 0;
}

sub dl_cmd {
	shift (@{$_[0]});
	my $cmd =    shift @{$_[0]};
	my $entity = shift @{$_[0]};
	my $value =  join ' ', @{$_[0]};
	print "\n";
	my $msg;

	if (defined $cmd) {
		if ($cmd eq 'enable') {
			if($entity eq 'nick') {
				if (savesetting 'dl_nicklist', '1') {
					$msg = "Nicks blacklist now enabled\n";
				}
			} elsif ($entity eq 'domain') {
				if (savesetting 'dl_domainlist', '1') {
					$msg = "Domains blacklist now enabled\n";
				}
			}
		} elsif ($cmd eq 'disable') {
			if($entity eq 'nick') {
				if (savesetting 'dl_nicklist', '0') {
					$msg = "Nicks blacklist now disabled\n";
				}
			} elsif ($entity eq 'domain') {
				if (savesetting 'dl_domainlist', '0') {
					$msg = "Domains blacklist now disabled\n";
				}
			}
		} elsif (($cmd eq 'show') or ($cmd eq 'info')) {
			$msg = '';

			if (listenabled 'dl_nicklist') {
				$msg .= "Nicks blacklist:    enabled\n";
			} else {
				$msg .= "Nicks blacklist:    disabled\n";
			}

			$msg .= 'Blacklisted nicks = ' . join ( ', ', loadlist ('dl_nicks')) . "\n";

			if (listenabled 'dl_domainlist') {
				$msg .= "Domains blacklist:  enabled\n";
			} else {
				$msg .= "Domains blacklist:  disabled\n";
			}

			$msg .= 'Blacklisted domains = ' . join ( ', ', loadlist ('dl_domains')) . "\n";
		} elsif ($cmd eq 'add') {
			if ((defined $entity) && (defined $value)) {
				if ($entity eq 'nick') {
					my @nicks = (loadlist ('dl_nicks'), $value);

					unless (savelist 'dl_nicks', @nicks) {
						$cmd = '';    undef $cmd;
						$entity = ''; undef $entity;
						$value = '';  undef $value;
						$msg = '';    undef $msg;
						$#nicks = -1; undef @nicks;
						return EAT_ALL;
					}

					$msg = sprintf "Nicks blacklist now: %s\n", join (', ', @nicks);
					$#nicks = -1; undef @nicks;
				} elsif ($entity eq 'domain') {
					my @domains = (loadlist ('dl_domains'), $value);

					unless (savelist 'dl_domains', @domains) {
						$cmd = '';      undef $cmd;
						$entity = '';   undef $entity;
						$value = '';    undef $value;
						$msg = '';      undef $msg;
						$#domains = -1; undef @domains;
						return EAT_ALL;
					}

					$msg = sprintf "Domains blacklist now: %s\n", join (', ', @domains);
					$#domains = -1; undef @domains;
				}
			}
		} elsif ($cmd eq 'del') {
			if ((defined $entity) and (defined $value)) {
				if ($entity eq 'nick') {
					my @list = loadlist 'dl_nicks';
					my @nicklist;

					foreach (@list) {
						next if ($_ eq $value);
						push @nicklist, $_;
					}

					$#list = -1; undef @list;

					unless (savelist 'dl_nicks', @nicklist) {
						$cmd = '';       undef $cmd;
						$entity = '';    undef $entity;
						$value = '';     undef $value;
						$msg = '';       undef $msg;
						$#nicklist = -1; undef @nicklist;
						return EAT_ALL;
					}

					$msg = sprintf "Nicks blacklist now: %s\n", join (', ', @nicklist);
					$#nicklist = -1; undef @nicklist;
				} elsif ($entity eq 'domain') {
					my @list = loadlist 'dl_domains';
					my @domainlist;

					foreach (@list) {
						next if ($_ eq $value);
						push @domainlist, $_;
					}

					$#list = -1; undef @list;

					unless (savelist 'dl_domains', @domainlist) {
						$cmd = '';         undef $cmd;
						$entity = '';      undef $entity;
						$value = '';       undef $value;
						$msg = '';         undef $msg;
						$#domainlist = -1; undef @domainlist;
						return EAT_ALL;
					}

					$msg = sprintf "Domains blacklist now: %s\n", join (', ', @domainlist);
					$#domainlist = -1; undef @domainlist;
				}
			}
		}
	}

	if (defined $msg) {
		print $msg;
	} else {
		print $help;
	}

	$cmd = '';    undef $cmd;
	$entity = ''; undef $entity;
	$value = '';  undef $value;
	$msg = '';    undef $msg;
	return EAT_ALL;
}

sub freehooks {
	foreach (@hooks) {
		unhook $_;
	}

	return EAT_ALL;
}
