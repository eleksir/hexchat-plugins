#!/usr/bin/perl

# HexChat Perl script
# Automatically save images that are linked in a channel to [hexchat-dir]/imgsave on linux/unices or %USERPROFILE%\Downloads on Windows
# You may need to create this directory first
# The bad_domains array may be used to exclude image URLs with domains matching any of a list of patterns. Set to an empty list to disable.

# TODO: enhance urlencode with punicode
# TODO: suppress any errors (errors only in debug mode)
# TODO: create menu and plugin-own ini-file or some sort of config (or add one more section to hexchat config, which is possible via api)
# TODO: fix bad behaving picture hostings that put wrong mime-types on content, tt-rss is one of them


use strict;
use warnings "all";

use threads;
use URI::URL;

my $wgetpath;

if (-f "/bin/wget") {
	$wgetpath = '/bin/wget';
} elsif (-f "/usr/bin/wget") {
	$wgetpath = '/usr/bin/wget';
} elsif (-f "/usr/local/bin/wget") {
	$wgetpath = '/usr/local/bin/wget';
}

sub hookfn;        # in defaults we trust: dunno arrayname/args name, but default values looks good :)
sub dlfunc(@);     # download thread
sub cdlfunc(@);    # thread, that checks and downloads stuff
sub is_picture($); # sub thar checks the mime-type
sub urlencode($);  # correctly encode url :)

my $script_name = "Image URL Auto Grabber and Downloader, wget flavour";
HexChat::register($script_name, '0.6-alpha1', 'Automatically grabs and downloads image URLs via wget');

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

			unless (-d sprintf("%s/imgsave", HexChat::get_info("configdir"))) {
				mkdir (sprintf("%s/imgsave", HexChat::get_info("configdir")));
			}

			$fn = HexChat::get_info("configdir") . "/imgsave/" . s/[^\w!., -#]/_/gr;

			my $th = threads->create(\&dlfunc, $_, $fn);
			$th->detach();

		} elsif ($_ =~ m{https?://([a-zA-Z0-9.-]+\.[a-zA-Z]+)/(?:.*)}) {
		# here we try to download _url_ that begins with https and does not ends with known file type
			my $full_url = $_;
			my $fqdn = $1;
			my $uri_part = $2;
			my $thr = threads->create(\&cdlfunc, $full_url);
			$thr->detach();
		}
	}
	return HexChat::EAT_NONE;
}

sub dlfunc(@) {
	my $file = shift; # 0
	my $url = shift;  # 1
	$url = urlencode($url);
	`$wgetpath -q -T 20 -O '$file' '$url'`;
	return 0;
}

sub cdlfunc(@) {
	my $url = shift;
	my $extension = is_picture($url);

	if (defined($extension)) {

		unless (-d sprintf("%s/imgsave", HexChat::get_info("configdir"))) {
			mkdir (sprintf("%s/imgsave", HexChat::get_info("configdir")));
		}

		my $fname = HexChat::get_info("configdir") . "/imgsave/" . s/[^\w!., -#]/_/gr . ".$extension";

		dlfunc($url, $fname);
	}
}

sub is_picture($) {
	my $url = shift;
	$url = urlencode($url);
	my $r = undef;

	$r = `$wgetpath --no-check-certificate -q --method=HEAD -S --timeout=15 "$url" 2>&1`;

	foreach (split(/\n/, $r)) {
		next unless($_ =~ /Content\-Type: (.+)/);
		$r = ($1); chomp($r);
		last;
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
