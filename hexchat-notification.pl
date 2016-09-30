# TODO: huge cleanup and code refactor required!
use strict;
use warnings "all";
use HexChat qw(:all);
use threads;
use threads::shared;

sub hookfn;
sub notify(@);
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

register($script_name, '0.5', 'Sends *nix desktop notifications');

HexChat::print("$script_name loaded\n");
hook_print('Channel Message', \&hookfn);
hook_print('Channel Msg Hilight', \&hookfn);
hook_print('Channel Action', \&hookfn);
hook_print('Channel Action Hilight', \&hookfn);
hook_command 'notify', \&notify_cmd, { 'help_text' => $help };

my $active = 0;
share($active);

sub hookfn {
	my ($nick, $text, $modechar) = @{$_[0]};
	my $channel = HexChat::get_info('channel');
	my $network = HexChat::get_info('network');
	$nick = '' unless(defined($nick));
	$channel = '' unless(defined($channel));
	$network = '' unless(defined($network));

# load settings, parse whitelists here
	my $nicklist = HexChat::plugin_pref_get('nicklist');
	unless (defined($nicklist)) {
		if (HexChat::plugin_pref_set('nicklist', '0') == 0) {
			HexChat::print("Unable to save settings for $script_name\n");
		}

		$nicklist = 0;
	}

	my $chanlist = HexChat::plugin_pref_get('chanlist');
	unless (defined($chanlist)) {
		if (HexChat::plugin_pref_set('chanlist', '0') == 0) {
			HexChat::print("Unable to save settings for $script_name\n");
		}

		$chanlist = 0;
	}

	my $netlist = HexChat::plugin_pref_get('netlist');
	unless (defined($netlist)) {
		if (HexChat::plugin_pref_set('netlist', '0') == 0) {
			HexChat::print("Unable to save settings for $script_name\n");
		}

		$netlist = 0;
	}

	unless ($nicklist == 0) {
		my $nicks = HexChat::plugin_pref_get('nicks');

		unless (defined($nicks)) {
			if (HexChat::plugin_pref_set('nicks', '') == 0) {
				HexChat::print("Unable to save settings for $script_name\n");
			}

			$nicks = '';
		}

		my @nicklist = split(/ /, $nicks);

		foreach (@nicklist) {
			next unless(defined($_));
			next unless($_ eq '');
			return EAT_NONE if ($_ eq $nick);
		}
	}

	unless ($chanlist == 0) {
		my $chans = HexChat::plugin_pref_get('chans');

		unless (defined($chans)) {
			if (HexChat::plugin_pref_set('chans', '') == 0) {
				HexChat::print("Unable to save settings for $script_name\n");
			}

			$chans = '';
		}

		my @chanlist = split(/ /, $chans);

		foreach (@chanlist) {
			next unless(defined($_));
			next unless($_ eq '');
			return EAT_NONE if ($_ eq $channel);
		}
	}

	unless ($nicklist == 0) {
		my $nicks = HexChat::plugin_pref_get('nicks');

		unless (defined($nicks)) {
			if (HexChat::plugin_pref_set('nicks', '') == 0) {
				HexChat::print("Unable to save settings for $script_name\n");
			}

			$nicks = '';
		}

		my @nicklist = split(/ /, $nicks);

		foreach (@nicklist) {
			next unless(defined($_));
			next unless($_ eq '');
			return EAT_NONE if ($_ eq $nick);
		}
	}

	unless ($netlist == 0) {
		my $nets = HexChat::plugin_pref_get('nets');

		unless (defined($nets)) {
			if (HexChat::plugin_pref_set('nets', '') == 0) {
				HexChat::print("Unable to save settings for $script_name\n");
			}

			$nets = '';
		}

		my @netlist = split(/ /, $nets);

		foreach (@netlist) {
			next unless(defined($_));
			next unless($_ eq '');
			return EAT_NONE if ($_ eq $network);
		}
	}
# settings are loaded

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

sub notify_cmd {
	my $cmd = $_[0][1] // undef;
	my $entity = $_[0][2] // undef;
	my $value = $_[0][3] // undef;

	HexChat::print($help) unless (defined($cmd));

	if ($cmd eq 'status') {
		my $nicklist = HexChat::plugin_pref_get('nicklist');
		unless (defined($nicklist)) {
			if (HexChat::plugin_pref_set('nicklist', '0') == 0) {
				HexChat::print("Unable to save settings for $script_name\n");
			}

			$nicklist = 0;
		}

		my $chanlist = HexChat::plugin_pref_get('chanlist');
		unless (defined($chanlist)) {
			if (HexChat::plugin_pref_set('chanlist', '0') == 0) {
				HexChat::print("Unable to save settings for $script_name\n");
			}

			$chanlist = 0;
		}

		my $netlist = HexChat::plugin_pref_get('netlist');
		unless (defined($netlist)) {
			if (HexChat::plugin_pref_set('netlist', '0') == 0) {
				HexChat::print("Unable to save settings for $script_name\n");
			}

			$netlist = 0;
		}

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
			if (HexChat::plugin_pref_set('nicklist', '1') == 0) {
				HexChat::print("Unable to save settings for $script_name]n");
			} else {
				HexChat::print("Nicks whitelist now enabled\n");
			}
		} elsif ($entity eq 'chan') {
			if (HexChat::plugin_pref_set('chanlist', '1') == 0) {
				HexChat::print("Unable to save settings for $script_name\n");
			} else {
				HexChat::print("Channel whitelist now enabled\n");
			}
		} elsif ($entity eq 'net') {
			if (HexChat::plugin_pref_set('netlist', '1') == 0) {
				HexChat::print("Unable to save settings for $script_name\n");
			} else {
				HexChat::print("Networks whitelist now enabled\n");
			}
		}
	} elsif ($cmd eq 'disable') {
		if($entity eq 'nick') {
			if (HexChat::plugin_pref_set('nicklist', '0') == 0) {
				HexChat::print("Unable to save settings for $script_name]n");
			} else {
				HexChat::print("Nicks whitelist now disabled\n");
			}
		} elsif ($entity eq 'chan') {
			if (HexChat::plugin_pref_set('chanlist', '0') == 0) {
				HexChat::print("Unable to save settings for $script_name\n");
			} else {
				HexChat::print("Channel whitelist now disabled\n");
			}
		} elsif ($entity eq 'net') {
			if (HexChat::plugin_pref_set('netlist', '0') == 0) {
				HexChat::print("Unable to save settings for $script_name\n");
			} else {
				HexChat::print("Networks whitelist now disabled\n");
			}
		}
	} elsif ($cmd eq 'show') {
		my $str = '';

		my $nicklist = HexChat::plugin_pref_get('nicklist');
		unless (defined($nicklist)) {
			if (HexChat::plugin_pref_set('nicklist', '0') == 0) {
				HexChat::print("Unable to save settings for $script_name\n");
			}

			$nicklist = 0;
		}

		if ($nicklist == 0) {
			$str .= "Nicks whitelist:    disabled\n";
		} else {
			$str .= "Nicks whitelist:    enabled\n";
		}

		my $nicks = HexChat::plugin_pref_get('nicks');
		unless (defined($nicks)) {
			if (HexChat::plugin_pref_set('nicks', '') == 0) {
				HexChat::print("Unable to save settings for $script_name\n");
			}

			$nicks = '';
		}

		$str .= "Whitelisted nicks = $nicks\n";

		my $chanlist = HexChat::plugin_pref_get('chanlist');
		unless (defined($chanlist)) {
			if (HexChat::plugin_pref_set('chanlist', '0') == 0) {
				HexChat::print("Unable to save settings for $script_name\n");
			}

			$chanlist = 0;
		}

		if ($chanlist == 0) {
			$str .= "Channel whitelist:  disabled\n";
		} else {
			$str .= "Channel whitelist:  enabled\n";
		}

		my $chans = HexChat::plugin_pref_get('chans');
		unless (defined($chans)) {
			if (HexChat::plugin_pref_set('chans', '') == 0) {
				HexChat::print("Unable to save settings for $script_name\n");
			}

			$chans = '';
		}

		$str .= "Whitelisted channels = $chans\n";

		my $netlist = HexChat::plugin_pref_get('netlist');
		unless (defined($netlist)) {
			if (HexChat::plugin_pref_set('netlist', '0') == 0) {
				HexChat::print("Unable to save settings for $script_name\n");
			}

			$netlist = 0;
		}

		if ($netlist == 0) {
			$str .= "Networks whitelist: disabled\n";
		} else {
			$str .= "Networks whitelist: enabled\n";
		}

		my $nets = HexChat::plugin_pref_get('nets');
		unless (defined($nets)) {
			if (HexChat::plugin_pref_set('nets', '') == 0) {
				HexChat::print("Unable to save settings for $script_name\n");
			}

			$nets = '';
		}

		$str .= "Whitelisted networks = $nets\n";

		HexChat::print($str);
		return HexChat::EAT_ALL;
	} elsif ($cmd eq 'add') {
		my $str = '';
		if ((defined($entity)) and (defined($value))) {
			if ($entity eq 'nick') {
				my $nicks = HexChat::plugin_pref_get('nicks');

				unless (defined($nicks)) {
					if (HexChat::plugin_pref_set('nicks', '') == 0) {
						HexChat::print("Unable to save settings for $script_name\n");
					}

					$nicks = '';
				}

				$nicks .= " $value";

				if (HexChat::plugin_pref_set('nicks', $nicks) == 0) {
					HexChat::print("Unable to save settings for $script_name\n");
					return HexChat::EAT_ALL;
				}

				HexChat::print("Nicks whitelist now: $nicks\n");
				return HexChat::EAT_ALL;
			} elsif ($entity eq 'chan') {
				my $chans = HexChat::plugin_pref_get('chans');

				unless (defined($chans)) {
					if (HexChat::plugin_pref_set('chans', '') == 0) {
						HexChat::print("Unable to save settings for $script_name\n");
					}

					$chans = '';
				}

				$chans .= " $value";

				if (HexChat::plugin_pref_set('chans', $chans) == 0) {
					HexChat::print("Unable to save settings for $script_name\n");
					return HexChat::EAT_ALL;
				}

				HexChat::print("Channels whitelist now: $chans\n");
				return HexChat::EAT_ALL;
			} elsif ($entity eq 'net') {
				my $nets = HexChat::plugin_pref_get('nets');

				unless (defined($nets)) {
					if (HexChat::plugin_pref_set('nets', '') == 0) {
						HexChat::print("Unable to save settings for $script_name\n");
					}

					$nets = '';
				}

				$nets .= " $value";

				if (HexChat::plugin_pref_set('nets', $nets) == 0) {
					HexChat::print("Unable to save settings for $script_name\n");
					return HexChat::EAT_ALL;
				}

				HexChat::print("Networks whitelist now: $nets\n");
				return HexChat::EAT_ALL;
			}
		}

	} elsif ($cmd eq 'del') {
		if ((defined($entity)) and (defined($value))) {
			if ($entity eq 'nick') {
				my $nicks = HexChat::plugin_pref_get('nicks');

				unless (defined($nicks)) {
					if (HexChat::plugin_pref_set('nicks', '') == 0) {
						HexChat::print("Unable to save settings for $script_name\n");
					}

					$nicks = '';
				}

				my @nicklist = split(/ /, $nicks);

				for (my $i = 0; $i < @nicklist; $i++) {
					$nicklist[$i] = '' if ($nicklist[$i] eq $value);
				}

				$nicks = join(' ', @nicklist);
				$nicks =~ s/ +/ /g;

				if (HexChat::plugin_pref_set('nicks', $nicks) == 0) {
					HexChat::print("Unable to save settings for $script_name\n");
					return HexChat::EAT_ALL;
				}

				HexChat::print("Nicks whitelist now: $nicks\n");
				return HexChat::EAT_ALL;
			}

			if ($entity eq 'chan') {
				my $chans = HexChat::plugin_pref_get('chans');

				unless (defined($chans)) {
					if (HexChat::plugin_pref_set('chans', '') == 0) {
						HexChat::print("Unable to save settings for $script_name\n");
					}

					$chans = '';
				}

				my @chanlist = split(/ /, $chans);

				for (my $i = 0; $i < @chanlist; $i++) {
					$chanlist[$i] = '' if ($chanlist[$i] eq $value);
				}

				$chans = join(' ', @chanlist);
				$chans =~ s/ +/ /g;

				if (HexChat::plugin_pref_set('chans', $chans) == 0) {
					HexChat::print("Unable to save settings for $script_name\n");
					return HexChat::EAT_ALL;
				}

				HexChat::print("Channels whitelist now: $chans\n");
				return HexChat::EAT_ALL;
			}

			if ($entity eq 'net') {
				my $nets = HexChat::plugin_pref_get('nets');

				unless (defined($nets)) {
					if (HexChat::plugin_pref_set('nets', '') == 0) {
						HexChat::print("Unable to save settings for $script_name\n");
					}

					$nets = '';
				}

				my @netlist = split(/ /, $nets);

				for (my $i = 0; $i < @netlist; $i++) {
					$netlist[$i] = '' if ($netlist[$i] eq $value);
				}

				$nets = join(' ', @netlist);
				$nets =~ s/ +/ /g;

				if (HexChat::plugin_pref_set('nets', $nets) == 0) {
					HexChat::print("Unable to save settings for $script_name\n");
					return HexChat::EAT_ALL;
				}

				HexChat::print("Networkss whitelist now: $nets\n");
				return HexChat::EAT_ALL;
			}

		}
	}

	HexChat::print($help);
	return HexChat::EAT_ALL;
}
