use strict;
use warnings "all";

sub hookfn;
my $script_name = "Notification plugin";
HexChat::register($script_name, '0.1', 'Sends *nix desktop notifications');

HexChat::print("$script_name loaded\n");
HexChat::hook_print('Channel Message', \&hookfn);
HexChat::hook_print('Channel Msg Hilight', \&hookfn);
HexChat::hook_print('Channel Action', \&hookfn);
HexChat::hook_print('Channel Action Hilight', \&hookfn);

sub hookfn {
	my ($nick, $text, $modechar) = @{$_[0]};
	my $channel = HexChat::get_info('channel');
	$channel = '' unless(defined($channel));
	$nick = '' unless(defined($nick));
	$text = '' unless(defined($text));
	$text =~ s/\"/\\"/g;
	my $topic = sprintf("%s at %s says:", $nick, $channel);
	`notify-send -u normal -t 10000 -a hexchat "$topic" -i hexchat "$text" &`;
	return HexChat::EAT_NONE;
}
