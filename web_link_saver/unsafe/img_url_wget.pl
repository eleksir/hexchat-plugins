# one of hexchat contributors said this on freenode's #hexchat
# 2017-11-26 15:36 < TingPing> eleksir, the hexchat api isn't thread safe
# on practice it developes to memory leak

use HexChat qw(:all);
use threads;
use threads::shared;

use strict;
use warnings "all";

use MIME::Base64;
use URI::URL;
my $IMAGEMAGICK = undef; # use on demand, perl that shipped with hexchat-2.12.4 on windows miss this module 
if ($^O ne 'cygwin') {   # cygwin 2.882 64-bit has broken Image::Magick
	$IMAGEMAGICK = eval {
		require Image::Magick;
		import Image::Magick qw(ping);
		return 1;
	}
}

sub dlfunc($);    # thread, that checks and downloads stuff
sub is_picture($);
sub urlencode($);
sub hookfn;
sub loadliststatus($);
sub loadlist($);
sub savelist(@);
sub savesetting(@);
sub dl_cmd;
sub freehooks;

my $wgetpath; share($wgetpath);

my $script_name = "Image URL Downloader";
HexChat::register($script_name, '0.10', 'Automatically downloads image URLs via wget', \&freehooks);

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

my $active = 0;
share($active);

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

			$active = 1;
			my $t = undef;

			do {
				$t = threads->create('dlfunc', $str);
				sleep 1 unless(defined($t));
			} unless (defined($t));

			$t->detach;
			undef $t;

			if ($active == 1) {
				HexChat::hook_timer( 100, sub { return REMOVE if ($active == 0); return KEEP; } );
			}
		}
	}

	@words = -1; undef @words;
	undef $nick; undef $text; undef $modechar;

	return HexChat::EAT_NONE;
}

sub dlfunc($) {
	my $url = shift;

	if (-f "/bin/wget") {
		$wgetpath = '/bin/wget';
	} elsif (-f "/usr/bin/wget") {
		$wgetpath = '/usr/bin/wget';
	} elsif (-f "/usr/local/bin/wget") {
		$wgetpath = '/usr/local/bin/wget';
	} elsif (-f "c:\\perl\\bin\\wget.exe") {
		$wgetpath = "c:\\perl\\bin\\wget.exe";
	} elsif (-f "c:\\perl64\\bin\\wget.exe") {
		$wgetpath = "c:\\perl64\\bin\\wget.exe";
	} elsif (-f "$ENV{'PROGRAMFILES'}\\perl\\bin\\wget.exe") {
		$wgetpath = "$ENV{'PROGRAMFILES'}\\perl\\bin\\wget.exe";
	} elsif (-f "$ENV{'PROGRAMFILES'}\\perl64\\bin\\wget.exe") {
		$wgetpath = "$ENV{'PROGRAMFILES'}\\perl64\\bin\\wget.exe";
	}

	my $extension = is_picture($url);

	if (defined($extension)) {
		my $savepath = sprintf("%s/imgsave", HexChat::get_info("configdir"));

		if ($^O eq 'MSWin32') {
			$savepath = $ENV{'USERPROFILE'} . '/Pictures';
		}

		mkdir ($savepath) unless (-d $savepath);

		if ( (lc($url) =~ /\.(gif|jpeg|png|webm|mp4)$/) and ($1 eq $extension) ){
			$savepath = $savepath . "/" . s/[^\w!., -#\?\:]/_/gr;
		} else {
			$savepath = $savepath . "/" . s/[^\w!., -#\?\:]/_/gr . ".$extension";
		}

		$url = urlencode($url);
		system($wgetpath, '--no-check-certificate', '-q', '-T', '20', '-O', $savepath, '-o', '/dev/null', "$url");

		if (($^O ne 'cygwin') and defined($IMAGEMAGICK)) {
			eval {
				if ($savepath =~ /(png|jpe?g|gif)$/i){
					my $im = Image::Magick->new();
					my $rename = 1;
					my (undef, undef, undef, $format) = $im->Ping($savepath);

					if (defined($format)) {
						$rename = 0 if (($format eq 'JPEG') and ($savepath =~ /jpe?g$/i));
						$rename = 0 if (($format eq 'GIF') and ($savepath =~ /gif$/i));
						$rename = 0 if (($format =~ /^PNG/) and ($savepath =~ /png$/i));
						rename $savepath, sprintf("%s.%s", $savepath, lc($format)) if ($rename == 1);
					}

					undef $im; undef $rename;
				}
			}
		}

		undef $savepath;
	}

	$active = 0;
	undef $url; undef $extension;
}

sub is_picture($) {
	my $url = shift;
	$url = urlencode($url);
	my $r = undef;

	$r = `$wgetpath --no-check-certificate -q --method=HEAD -S --timeout=5 "$url" 2>&1`;
	undef $url;

	if ($? == 0) {
		foreach (split(/\n/, $r)) {
			next unless($_ =~ /Content\-Type: (.+)/);
			$r = ($1); chomp($r);
			last;
		}

		if (defined($r)) {
			if    ($r =~ /^image\/gif/)  { $r = 'gif'; }
			elsif ($r =~ /^image\/jpe?g/){ $r = 'jpeg';}
			elsif ($r =~ /^image\/png/)  { $r = 'png'; }
			elsif ($r =~ /^video\/webm/) { $r = 'webm';}
			elsif ($r =~ /^video\/mp4/)  { $r = 'mp4'; }
			else                         { $r = undef; }
		} else {
			$r = undef;
		}
	} else {
		$r = undef;
	}

	return $r;
}

sub urlencode($) {
	my $url = shift;
	my $urlobj = url $url;
	$url = $urlobj->as_string;
	undef $urlobj;
	return $url;
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
			if ($entity eq 'nick') {
				if (defined(savesetting('dl_nicklist', '1'))) {
					$msg = "Nicks blacklist now enabled\n";
				}
			} elsif ($entity eq 'domain') {
				if (defined(savesetting('dl_domainlist', '1'))) {
					$msg = "Domains blacklist now enabled\n";
				}
			}
		} elsif ($cmd eq 'disable') {
			if ($entity eq 'nick') {
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

	unless (defined($msg)) {
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
