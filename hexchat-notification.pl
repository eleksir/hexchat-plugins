use strict;
use warnings "all";
use HexChat qw(:all);
use threads;
use threads::shared;

sub hookfn;
sub notify(@);
sub timeraction;

my $script_name = "Notification plugin";
register($script_name, '0.2', 'Sends *nix desktop notifications');

HexChat::print("$script_name loaded\n");
hook_print('Channel Message', \&hookfn);
hook_print('Channel Msg Hilight', \&hookfn);
hook_print('Channel Action', \&hookfn);
hook_print('Channel Action Hilight', \&hookfn);

my $active = 0;
share($active);

sub hookfn {
	my ($nick, $text, $modechar) = @{$_[0]};
	my $channel = HexChat::get_info('channel');
	$channel = '' unless(defined($channel));
	$nick = '' unless(defined($nick));
	HexChat::strip_code($text);
	$text =~ s/\"/\\"/g;
	my $topic = sprintf("%s at %s says:\n", $nick, $channel);
	$active = 1;
	my $t = undef;

	do {
		$t = threads->create(\&notify, $topic, $text);
		sleep 1 unless(defined($t));
	} unless (defined($t));

	$t->detach;

	if ($active == 1) {
		hook_timer( 500, \&timeraction);
	}
	
	return EAT_NONE;
}

sub notify(@) {
	my($topic, $text) = @_;
	`notify-send -u normal -t 12000 -a hexchat "$topic" -i hexchat "$text"`;
	$active = 0;
}

sub timeraction {
	if ($active == 0) {
		return REMOVE;
	} else {
		return KEEP;
	}
}
