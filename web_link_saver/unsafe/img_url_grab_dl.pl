#!/usr/bin/perl

# WARNING: this script is Proof of Concept and contains incorrect logic
#          it placed here only for historical reasons

# HexChat Perl script
# Automatically save images that are linked in a channel to [hexchat-dir]/imgsave on linux/unices or %USERPROFILE%\Downloads on Windows
# You may need to create this directory first
# The bad_domains array may be used to exclude image URLs with domains matching any of a list of patterns. Set to an empty list to disable.
# Written by Jonathan Rennison (j.g.rennison@gmail.com)
# 2012-02-18
# Loosely based on http://pastebin.com/QE24QJ8p by Derek Meister
# 2016-05-02
# coding style fixes, port to windows/activeperl, add failover to some different download modules make WWW::Curl default method, as it thread safe and more robust than LWP
# 2016-05-15
# coding style fixes, added content guessing for links that does not contain file extension, not for all backends (powershell is missing), WWW::Curl is dropped due to many troubles with symbols loading

# TODO: enhance urlencode with punicode
# TODO: refuse HTTP::Tiny for ipv6-only host (due to lack of ipv4 suppoort in this module)
# TODO: looks like we definely need dns resolver here to to guess ipv6-only hosts
# TODO: suppress any errors (errors only in debug mode)


use strict;
use warnings "all";

use threads;
use URI::URL;

# standard way (looks like this module should be in perl package, unless it is split-package)
my $got_HTTP_Tiny = 0;
eval { require HTTP::Tiny };

unless ($@) {
	$got_HTTP_Tiny = 1;
	HTTP::Tiny->import();
}

# fat way
my $got_LWP_Simple = 0;
my $got_wget = 0;
my $got_curl = 0;
my $curlpath;
my $wgetpath;
my $got_powershell = 0;

if ($got_HTTP_Tiny == 0) {
	eval { require LWP::Simple };

	unless ($@) {
		$got_LWP_Simple = 1;
		LWP::Simple->import();
	} else {

# failover way
		if (-f "/bin/wget") {
			$got_wget = 1;
			$wgetpath = '/bin/wget';
		} elsif (-f "/usr/bin/wget") {
			$got_wget = 1;
			$wgetpath = '/usr/bin/wget';
		} elsif (-f "/usr/local/bin/wget") {
			$got_wget = 1;
			$wgetpath = '/usr/local/bin/wget';
		}

		if (-f "/bin/curl") {
			$got_curl = 1;
			$curlpath = '/bin/curl';
		} elsif (-f "/usr/bin/curl") {
			$got_curl = 1;
			$curlpath = '/usr/bin/curl';
		} elsif (-f "/usr/local/bin/curl") {
			$got_curl = 1;
			$curlpath = '/usr/local/bin/curl';
		}

		if ($^O eq 'MSWin') {
			$got_powershell = 1;
		}

	}
}
sub hookfn;        # in defaults we trust: dunno arrayname/args name, but default values looks good :)
sub dlfunc(@);     # download thread
sub cdlfunc(@);    # thread, that checks and downloads stuff
sub is_picture($); # sub thar checks the mime-type
sub urlencode($);  # correctly encode url :)

my $script_name = "Image URL Auto Grabber and Downloader";
HexChat::register($script_name, '0.6-alpha1', 'Automatically grabs and downloads image URLs');

HexChat::print("$script_name loaded\n");
HexChat::hook_print('Channel Message', \&hookfn);
HexChat::hook_print('Channel Msg Hilight', \&hookfn);
HexChat::hook_print('Channel Action', \&hookfn);
HexChat::hook_print('Channel Action Hilight', \&hookfn);

my @bad_domains = ();	#array of regexs for domain name exclusion
#my @bad_domains = (qr/^(?:.*\.)?example\.com$/, qr/\bbannedword\b/, qr/^name\./);		#example, exclude: example.com and subdomains, domains containing the term bannedword, and domains starting with name.

sub hookfn {
	my ($nick, $text, $modechar) = @{$_[0]};
	my @words = split(/\s+/, $text);

	foreach (@words) {
		# here we try to catch string that can contain http or https at beginning (assume http if none)
		# and after all ends with known extension
		if ($_ =~ m{^(?:https?://)?([a-zA-Z0-9.-]+\.[a-zA-Z]+)/(?:.*)\.(?:jpe?g|png|gif|mp4|webm)$}i) {

			foreach my $re (@bad_domains) {
				return HexChat::EAT_NONE if ($1 =~ $re);
			}

			# reconstruct url if it does not contain proto schema
			if ( $_ !~ m{^https?://} ) {
				$_="http://".$_;
			}
			# create filename
			my $fn;

			if ( $^O eq 'MSWin32' ) {
				$fn = $ENV{USERPROFILE} . "\\Downloads\\" . s/[^\w!., -#]/_/gr;
			} else {

				unless (-d sprintf("%s/imgsave", HexChat::get_info("configdir"))) {
					mkdir (sprintf("%s/imgsave", HexChat::get_info("configdir")));
				}

				$fn = HexChat::get_info("configdir") . "/imgsave/" . s/[^\w!., -#]/_/gr;
			}

			if ($got_HTTP_Tiny == 1) {
				my $th = threads->create(\&dlfunc, $_, $fn);
				$th->detach();
			} elsif ($got_LWP_Simple == 1) {

				if($_ =~ m{^https://}) {
					LWP::Simple::mirror($_, $fn);	# LWP SSL is not thread safe
				} else {
					my $th = threads->create(\&dlfunc, $_, $fn);
					$th->detach();
				}

			} else {
				my $th = threads->create(\&dlfunc, $_, $fn);
				$th->detach();
			}

		} elsif ($_ =~ m{https?://([a-zA-Z0-9.-]+\.[a-zA-Z]+)/(?:.*)}) {
		# here we try to download _url_ that begins with https and does not ends with known file type
			my $full_url = $_;
			my $fqdn = $1;
			my $uri_part = $2;

			if ($got_HTTP_Tiny == 1) {
				my $thr = threads->create(\&cdlfunc, $full_url);
				$thr->detach();
			} elsif ($got_LWP_Simple == 1) {

				if ($full_url =~ m{^https://}) {
					cdlfunc($full_url);
				} else {
					my $thr = threads->create(\&cdlfunc, $full_url);
					$thr->detach();
				}

			} else {
				my $thr = threads->create(\&cdlfunc, $full_url);
				$thr->detach();
			}

		}
	}
	return HexChat::EAT_NONE;
}

sub dlfunc(@) {
	my $file = shift; # 0
	my $url = shift;  # 1
	$url = urlencode($url);

	if ($got_HTTP_Tiny == 1) {
		my $http = HTTP::Tiny->new();
		$http->mirror($file, $url);
		undef $http;
	} elsif ($got_LWP_Simple == 1) {
		LWP::Simple::mirror($file, $url);
	} elsif ($got_wget == 1) {
		`$wgetpath -q -T 20 -O '$file' '$url'`;
	} elsif ($got_curl == 1) {
		`$curlpath -k -L -m 20 -o '$file' '$url'`;
	} elsif ($got_powershell == 1) {
		`powershell -command "& { (New-Object Net.WebClient).DownloadFile('$file', '$url') }"`;
	}

	return 0;
}

sub cdlfunc(@) {
	my $url = shift;
	my $extension = is_picture($url);

	if (defined($extension)) {
		my $fname;

		if ( $^O eq 'MSWin32' ) {
			$fname = $ENV{USERPROFILE} . "\\Downloads\\" . s/[^\w!., -#]/_/gr . ".$extension";
		} else {

			unless (-d sprintf("%s/imgsave", HexChat::get_info("configdir"))) {
				mkdir (sprintf("%s/imgsave", HexChat::get_info("configdir")));
			}

			$fname = HexChat::get_info("configdir") . "/imgsave/" . s/[^\w!., -#]/_/gr . ".$extension";
		}

		dlfunc($url, $fname);
	}
}

sub is_picture($) {
	my $url = shift;
	$url = urlencode($url);
	my $r = undef;

	if  ($got_HTTP_Tiny == 1) {
		my $response = HTTP::Tiny->new->head($url);
		$r = ${$response->{headers}}{'content-type'};
	} elsif ($got_LWP_Simple == 1) {
		$r = (LWP::Simple::head($url))[0];
	} elsif ($got_wget == 1) {
		$r = `$wgetpath --no-check-certificate -q --method=HEAD -S --timeout=15 "$url" 2>&1`;

		foreach (split(/\n/, $r)) {
			next unless($_ =~ /Content\-Type: (.+)/);
			$r = ($1); chomp($r);
			last;
		}

	} elsif ($got_curl == 1) {
		$r = `$curlpath -I -k  -f -s -m 15 "$url"`;

		foreach (split(/\n/, $r)) {
			next unless($_ =~ /Content\-Type: (.+)/);
			$r = ($1); chomp($r);
			last;
		}

	}

	if (defined($r)) {
		if ($r =~ /^image\/gif/)  {return 'gif';};
		if ($r =~ /^image\/jpe?g/){return 'jpeg';};
		if ($r =~ /^image\/png/)  {return 'png';};
		if ($r =~ /^video\/webm/) {return 'webm';};
		if ($r =~ /^video\/mp4/)  {return 'mp4';};
	}

	return undef;
}

sub urlencode($) {
	my $url = shift;
	my $urlobj = url $url;
	$url = $urlobj->as_string;
	undef $urlobj;
	return $url;
}

__END__
