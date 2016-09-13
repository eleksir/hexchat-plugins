#!/usr/bin/perl

# HexChat Perl script
# Automatically save images that are linked in a channel to [hexchat-dir]/imgsave on linux/unices
# The bad_domains array may be used to exclude image URLs with domains matching any of a list of patterns. Set to an empty list to disable.

# TODO: enhance urlencode with punicode
# TODO: create menu and plugin-own ini-file or some sort of config (or add one more section to hexchat config, which is possible via api)

use strict;
use warnings "all";

use URI::URL;
use Image::Magick;

my $wgetpath;

if (-f "/bin/wget") {
	$wgetpath = '/bin/wget';
} elsif (-f "/usr/bin/wget") {
	$wgetpath = '/usr/bin/wget';
} elsif (-f "/usr/local/bin/wget") {
	$wgetpath = '/usr/local/bin/wget';
}

sub dlfunc(@);     # download thread
sub cdlfunc($);    # thread, that checks and downloads stuff
sub is_picture($); # sub that checks mime-type given by the web server, this check should be used only to
                   # detect that given url contain picture or video, after download we should check mime-type
                   # again and rename file if needed
sub urlencode($);  # correctly encode url :)
sub hookfn;        # in defaults we trust: dunno arrayname/args name, but default values looks good :)


my $script_name = "Image URL Auto Grabber and Downloader, wget flavour";
HexChat::register($script_name, '0.6', 'Automatically grabs and downloads image URLs via wget');

HexChat::print("$script_name loaded\n");
HexChat::hook_print('Channel Message', \&hookfn);
HexChat::hook_print('Channel Msg Hilight', \&hookfn);
HexChat::hook_print('Channel Action', \&hookfn);
HexChat::hook_print('Channel Action Hilight', \&hookfn);

my @bad_domains = ();	#array of regexs for domain name exclusion
#my @bad_domains = (qr/^(?:.*\.)?example\.com$/, qr/\bbannedword\b/, qr/^name\./);		#example, exclude: example.com and subdomains, domains containing the term bannedword, and domains starting with name.

sub dlfunc(@) {
	my $url = shift;
	my $file = shift;

	$url = urlencode($url);
	`$wgetpath --no-check-certificate -q -T 20 -O '$file' -o /dev/null '$url'`;
	
	if ($file =~ /(png|jpe?g|gif)$/i){
		my $im = Image::Magick->new();
		my $rename = 1;
		my (undef, undef, undef, $format) = $im->Ping($file);

		if (defined($format)) {
			$rename = 0 if (($format eq 'JPEG') and ($file =~ /jpe?g$/i));
			$rename = 0 if (($format eq 'GIF') and ($file =~ /gif$/i));
			$rename = 0 if (($format =~ /^PNG/) and ($file =~ /png$/i));

			if ($rename == 1) {
				rename $file, sprintf("%s.%s", $file, lc($format));
			}
		}
	}

	return 0;
}

sub cdlfunc($) {
	my $url = shift;
	my $extension = is_picture($url);

	if (defined($extension)) {

		my $savepath = sprintf("%s/imgsave", HexChat::get_info("configdir"));

		unless (-d $savepath) {
			mkdir ($savepath);
		}

		$savepath = $savepath . "/" . s/[^\w!., -#]/_/gr . ".$extension";

		if (lc($url) =~ /\.(gif|jpeg|png|webm|mp4)$/) {
		
			if ($1 eq $extension) {
				$savepath = HexChat::get_info("configdir") . "/imgsave/" . s/[^\w!., -#]/_/gr;
			}

		}

		dlfunc($url, $savepath);
	}
}

sub is_picture($) {
	my $url = shift;
	$url = urlencode($url);
	my $r = undef;

	$r = `$wgetpath --no-check-certificate -q --method=HEAD -S --timeout=5 "$url" 2>&1`;

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

sub hookfn {
	my ($nick, $text, $modechar) = @{$_[0]};
	my @words = split(/\s+/, $text);

	foreach (@words) {
		# here we try to catch string that can contain http or https at beginning (assume http if none)
		# and after all ends with known extension
		if ($_ =~ m{https?://([a-zA-Z0-9.-]+\.[a-zA-Z]+)/(?:.*)}) {
			cdlfunc($_);
		}
	}

	return HexChat::EAT_NONE;
}

__END__
