use strict;
use warnings "all";
use HexChat qw(:all);
use threads;
use threads::shared;
use MIME::Base64;

sub loadliststatus($);
sub loadlist($);
sub savelist(@);
sub savesetting(@);
sub notify(@);
sub hookfn;
sub freehooks;
sub timeraction;
sub notify_cmd;

my $script_name = "Notification plugin";
my $help = 'Usage:
/notify enable nick|chan|net     - enables apropriate whitelist
/notify disable nick|chan|net    - disables apropriate whitelist
/notify add nick|chan|net <name> - adds <name> to apropriate whitelist
/notify del nick|chan|net <name> - removes <name> from apropriate whitelist
/notify status                   - shows statuses of whitelists
/notify show                     - shows whitelists and their statuses
';

register($script_name, '0.8.1', 'Sends *nix desktop notifications', \&freehooks);

HexChat::print("$script_name loaded\n");
my @hooks;
push @hooks, hook_print('Channel Message', \&hookfn);
push @hooks, hook_print('Channel Msg Hilight', \&hookfn);
push @hooks, hook_print('Channel Action', \&hookfn);
push @hooks, hook_print('Channel Action Hilight', \&hookfn);
push @hooks, hook_command('notify', \&notify_cmd);

my $active = 0;
share($active);

sub hookfn {
	my ($nick, $text, $modechar) = @{$_[0]};
	my $channel = HexChat::get_info('channel');
	my $network = HexChat::get_info('network');
	$nick =    '' unless(defined($nick));
	$channel = '' unless(defined($channel));
	$network = '' unless(defined($network));

# load settings, parse whitelists here
	my $flag = 1; # show notification
	my $nicklist = loadliststatus('nicklist');
	my $chanlist = loadliststatus('chanlist');
	my $netlist =  loadliststatus('netlist');
	$flag = 0 if (($nicklist != 0) or ($chanlist != 0) or ($netlist != 0));

	if ($nicklist != 0) {
		my @nicklist = loadlist('nicks');

		foreach (@nicklist) {
			next unless(defined($_));
			next if($_ eq '');
			$flag = 1 if ($_ eq $nick);
		}
	}

	if (($chanlist != 0) and ($flag == 0)) {
		my @chanlist = loadlist('chans');

		foreach (@chanlist) {
			next unless(defined($_));
			next if($_ eq '');
			$flag = 1 if ($_ eq $channel);
		}
	}

	if (($netlist != 0) and ($flag == 0)) {
		my @netlist = loadlist('nets');

		foreach (@netlist) {
			next unless(defined($_));
			next if($_ eq '');
			$flag = 1 if ($_ eq $network);
		}
	}

# settings are loaded
	return EAT_NONE if ($flag == 0);

	HexChat::strip_code($text);
	$text =~ s/\"/\\"/g;
	my $topic = sprintf("%s at %s says:\n", $nick, $channel);
	$active = 1;
	my $t = undef;

	do {
		$t = threads->create('notify', $topic, $text);
		sleep 1 unless(defined($t));
	} unless (defined($t));

	$t->detach;

	if ($active == 1) {
		hook_timer( 500, \&timeraction);
	}
	
	undef $nick;     undef $text;     undef $modechar;
	undef $channel;  undef $network;
	undef $flag;
	undef $nicklist; undef $chanlist; undef $netlist;

	return EAT_NONE;
}

sub notify(@) {
	my($topic, $text) = @_;
	system("notify-send", "-u", "normal", "-t", "12000", "-a", "hexchat", $topic, "-i", "hexchat", $text);
	$active = 0;
	undef $topic; undef $text;
}

sub timeraction {
	if ($active == 0) {
		return REMOVE;
	} else {
		return KEEP;
	}
}

sub notify_cmd {
	shift(@{$_[0]});
	my $cmd = shift(@{$_[0]});
	my $entity = shift(@{$_[0]});
	my $value = join(' ', @{$_[0]});

	unless (defined($cmd)) {
		HexChat::print($help);
		return HexChat::EAT_ALL;
	}

	if ($cmd eq 'info') {
		my $network = HexChat::get_info('network') // 'unknown';
		HexChat::printf("Network name for whitelist: %s\n", $network);
		return HexChat::EAT_ALL;
	} elsif ($cmd eq 'status') {
		my $nicklist = loadliststatus('nicklist');
		my $chanlist = loadliststatus('chanlist');
		my $netlist =  loadliststatus('netlist');

		if (($nicklist == 0) and ($chanlist == 0) and ($netlist == 0)) {
			HexChat::print("All whitelists are disbled, will not apply any filters, and be show all notifications.\n");
			return HexChat::EAT_ALL;
		}

		my $str = '';

		if ($nicklist == 0) { $str .= "Nicks whitelist:    disabled\n"; }
		else { $str .= "Nicks whitelist:    enabled\n"; }

		if ($chanlist == 0) { $str .= "Channel whitelist:  disabled\n"; }
		else { $str .= "Channel whitelist:  enabled\n"; }

		if ($netlist == 0) { $str .= "Networks whitelist: disabled\n"; }
		else { $str .= "Networks whitelist: enabled\n"; }

		HexChat::print($str);
		return HexChat::EAT_ALL;
	} elsif ($cmd eq 'enable') {
		if($entity eq 'nick') {
			if (defined(savesetting('nicklist', '1'))) {
				HexChat::print("Nicks whitelist now enabled\n");
			}
		} elsif ($entity eq 'chan') {
			if (defined(savesetting('chanlist', '1'))) {
				HexChat::print("Channel whitelist now enabled\n");
			}
		} elsif ($entity eq 'net') {
			if (defined(savesetting('netlist', '1'))) {
				HexChat::print("Networks whitelist now enabled\n");
			}
		}

		return HexChat::EAT_ALL;
	} elsif ($cmd eq 'disable') {
		if($entity eq 'nick') {
			if (defined(savesetting('nicklist', '0'))) {
				HexChat::print("Nicks whitelist now disabled\n");
			}
		} elsif ($entity eq 'chan') {
			if (defined(savesetting('chanlist', '0'))) {
				HexChat::print("Channel whitelist now disabled\n");
			}
		} elsif ($entity eq 'net') {
			if (defined(savesetting('netlist', '0'))) {
				HexChat::print("Networks whitelist now disabled\n");
			}
		}

		return HexChat::EAT_ALL;
	} elsif ($cmd eq 'show') {
		my $str = '';

		if (loadliststatus('nicklist') == 0) {
			$str .= "Nicks whitelist:    disabled\n";
		} else {
			$str .= "Nicks whitelist:    enabled\n";
		}

		$str .= "Whitelisted nicks = " . join( ', ', loadlist('nicks')) ."\n";

		if (loadliststatus('chanlist') == 0) {
			$str .= "Channel whitelist:  disabled\n";
		} else {
			$str .= "Channel whitelist:  enabled\n";
		}

		$str .= "Whitelisted channels = " . join( ', ', loadlist('chans')) . "\n";

		if (loadliststatus('netlist') == 0) {
			$str .= "Networks whitelist: disabled\n";
		} else {
			$str .= "Networks whitelist: enabled\n";
		}

		$str .= "Whitelisted networks = " . join( ', ', loadlist('nets')) . "\n";

		HexChat::print($str);
		return HexChat::EAT_ALL;
	} elsif ($cmd eq 'add') {
		my $str = '';
		if ((defined($entity)) and (defined($value))) {
			if ($entity eq 'nick') {
				my @nicks = (loadlist('nicks'), $value);

				unless (defined(savelist('nicks', @nicks))) {
					return HexChat::EAT_ALL;
				}

				HexChat::printf("Nicks whitelist now: %s\n", join(', ', @nicks));
				return HexChat::EAT_ALL;
			} elsif ($entity eq 'chan') {
				my @chans = (loadlist('chans'), $value);

				unless (defined(savelist('chans', @chans))) {
					return HexChat::EAT_ALL;
				}

				HexChat::printf("Channels whitelist now: %s\n", join(', ', @chans));
				return HexChat::EAT_ALL;
			} elsif ($entity eq 'net') {
				my @nets = (loadlist('nets'), $value);

				unless (defined(savelist('nets', @nets))) {
					return HexChat::EAT_ALL;
				}

				HexChat::printf("Networks whitelist now: %s\n", join(', ', @nets));
				return HexChat::EAT_ALL;
			}
		}

		return HexChat::EAT_ALL;
	} elsif ($cmd eq 'del') {
		if ((defined($entity)) and (defined($value))) {
			if ($entity eq 'nick') {
				my @list = loadlist('nicks');
				my @nicklist;

				foreach (@list) {
					next if ($_ eq $value);
					push @nicklist, $_;
				}

				@list = -1; undef @list;

				unless (defined(savelist('nicks', @nicklist))) {
					return HexChat::EAT_ALL;
				}

				HexChat::printf("Nicks whitelist now: %s\n", join(', ', @nicklist));
				return HexChat::EAT_ALL;
			}

			if ($entity eq 'chan') {
				my @list = loadlist('chans');
				my @chanlist;

				foreach (@list) {
					next if($_ eq $value);
					push @chanlist, $_;
				}

				@list = -1; undef @list;

				unless (defined(savelist('chans', @chanlist))) {
					return HexChat::EAT_ALL;
				}

				HexChat::printf("Channels whitelist now: %s\n", join(', ', @chanlist));
				return HexChat::EAT_ALL;
			}

			if ($entity eq 'net') {
				my @list = loadlist('nets');
				my @netlist;

				foreach (@list) {
					HexChat::printf("_: %s, value: %s", $_, $value);
					next if($_ eq $value);
					push @netlist, $_;
				}

				@list = -1; undef @list;

				unless (defined(savelist('nets', @netlist))) {
					return HexChat::EAT_ALL;
				}

				HexChat::printf("Networks whitelist now: %s\n", join(', ', @netlist));
				return HexChat::EAT_ALL;
			}

		}

		return HexChat::EAT_ALL;
	}

	HexChat::print($help);
	return HexChat::EAT_ALL;
}

sub loadliststatus($){
	my $listtype = shift;
	my $list = HexChat::plugin_pref_get($listtype);

	unless (defined($list)) {
		savesetting('list', '0');
		$list = 0;
	}

	undef $listtype;
	return $list;
}

sub loadlist($){
	my $setting = shift;
	my $val = HexChat::plugin_pref_get($setting);

	unless (defined($val)) {
		savesetting($setting, encode_base64(''));
		$val = '';
	}

	my @values = map { decode_base64($_); } split(/ /, $val);
	undef $setting; undef $val;
	return @values;
}

sub savelist(@) {
	my $setting = shift;
	my @list = map { encode_base64($_); } @_;
	my $value = join(' ', @list);
	return savesetting($setting, $value);
}

sub savesetting(@) {
	my $setting = shift;
	my $value = shift;

	if (HexChat::plugin_pref_set($setting, $value) == 0) {
		HexChat::printf("Unable to save settings for %s\n", $script_name);
		return undef;
	}

	undef $setting;
	return 1;
}

sub freehooks {
	foreach (@hooks) {
		HexChat::unhook($_);
	}
	
	return HexChat::EAT_ALL;
}
