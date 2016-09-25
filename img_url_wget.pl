use HexChat qw(:all);
use threads;
use threads::shared;

use strict;
use warnings "all";

use URI::URL;
use Image::Magick;

sub dlfunc(@);
sub cdlfunc($);    # thread, that checks and downloads stuff
sub is_picture($);
sub urlencode($);
sub hookfn;

my $wgetpath;

if (-f "/bin/wget") {
	$wgetpath = '/bin/wget';
} elsif (-f "/usr/bin/wget") {
	$wgetpath = '/usr/bin/wget';
} elsif (-f "/usr/local/bin/wget") {
	$wgetpath = '/usr/local/bin/wget';
}

my $script_name = "Image URL Auto Grabber and Downloader, wget flavour";
HexChat::register($script_name, '0.8', 'Automatically grabs and downloads image URLs via wget');

HexChat::print("$script_name loaded\n");
HexChat::hook_print('Channel Message', \&hookfn);
HexChat::hook_print('Channel Msg Hilight', \&hookfn);
HexChat::hook_print('Channel Action', \&hookfn);
HexChat::hook_print('Channel Action Hilight', \&hookfn);

my $active = 0;
share($active);

sub hookfn {
	my ($nick, $text, $modechar) = @{$_[0]};
	my @words = split(/\s+/, $text);

	foreach (@words) {
		if ($_ =~ m{https?://([a-zA-Z0-9.-]+\.[a-zA-Z]+)/(?:.*)}) {
			$active = 1;
			threads->create(\&cdlfunc, $_)->detach;

			if ($active == 1) {
				HexChat::hook_timer( 100, sub { return REMOVE if ($active == 0); return KEEP; } );
			}
		}
	}

	return HexChat::EAT_NONE;
}

sub cdlfunc($) {
	my $url = shift;
	my $extension = is_picture($url);

	if (defined($extension)) {
		my $savepath = sprintf("%s/imgsave", HexChat::get_info("configdir"));
		mkdir ($savepath) unless (-d $savepath);
		$savepath = $savepath . "/" . s/[^\w!., -#]/_/gr . ".$extension";

		if ( (lc($url) =~ /\.(gif|jpeg|png|webm|mp4)$/) and ($1 eq $extension) ){
				$savepath = HexChat::get_info("configdir") . "/imgsave/" . s/[^\w!., -#]/_/gr;
		}

		dlfunc($url, $savepath);
	}

	$active = 0;
}

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
			rename $file, sprintf("%s.%s", $file, lc($format)) if ($rename == 1);
		}
	}

	return 0;
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
