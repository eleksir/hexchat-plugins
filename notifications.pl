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
sub encodestr;

my $script_name = "Notification plugin";
my $help = 'Usage:
/notify enable nick|chan|net     - enables apropriate whitelist
/notify disable nick|chan|net    - disables apropriate whitelist
/notify add nick|chan|net <name> - adds <name> to apropriate whitelist
/notify del nick|chan|net <name> - removes <name> from apropriate whitelist
/notify status                   - shows statuses of whitelists
/notify show                     - shows whitelists and their statuses
';

register($script_name, '0.9.1', 'Sends *nix desktop notifications', \&freehooks);

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
	my $channel = HexChat::get_info('channel') // '';
	my $network = HexChat::get_info('network') // '';
	$nick =    '' unless(defined($nick));

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

			if ($_ eq $nick) {
				$flag = 1;
				last;
			}
		}
	}

	if (($chanlist != 0) and ($flag == 0)) {
		my @chanlist = loadlist('chans');

		foreach (@chanlist) {
			next unless(defined($_));
			next if($_ eq '');

			if ($_ eq $channel) {
				$flag = 1;
				last;
			}
		}
	}

	if (($netlist != 0) and ($flag == 0)) {
		my @netlist = loadlist('nets');

		foreach (@netlist) {
			next unless(defined($_));
			next if($_ eq '');

			if ($_ eq $network){
				$flag = 1;
				last;
			}
		}
	}

# settings are loaded
	if ($flag == 1) {
		$active = 1;
		my $t = undef;

		do {
			$t = threads->create('notify', $channel, $nick, $text);
			sleep 1 unless(defined($t));
		} unless (defined($t));

		$t->detach;

		if ($active == 1) {
			hook_timer( 500, \&timeraction);
		}
	}

	undef $nick;     undef $text;     undef $modechar;
	undef $channel;  undef $network;
	undef $flag;
	undef $nicklist; undef $chanlist; undef $netlist;

	return EAT_NONE;
}

sub notify(@) {
	my($channel, $nick, $text) = @_;
# notify-send|notification daemons are use limited html formatting for message body, so we have
# either use only topic without body or encode message body, which is a bit resource hungry
	HexChat::strip_code($text);
	HexChat::strip_code($nick);
	$text = encodestr($text);
	$nick = encodestr($nick);
	my $topic = sprintf("%s at %s says:\n", $nick, $channel);
	system("notify-send", "-u", "normal", "-t", "12000", "-a", "hexchat", $topic, "-i", "hexchat", $text);
	undef $channel, undef $nick, undef $text; undef $topic;
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
	shift(@{$_[0]});
	my $cmd = shift(@{$_[0]});
	my $entity = shift(@{$_[0]});
	my $value = join(' ', @{$_[0]});
	HexChat::print("\n");
	my $msg = undef;

	if (defined($cmd)) {
		if ($cmd eq 'info') {
			my $network = HexChat::get_info('network') // 'unknown';
			$msg = sprintf("Network name for whitelist: %s\n", $network);
		} elsif ($cmd eq 'status') {
			my $nicklist = loadliststatus('nicklist');
			my $chanlist = loadliststatus('chanlist');
			my $netlist =  loadliststatus('netlist');

			if (($nicklist == 0) and ($chanlist == 0) and ($netlist == 0)) {
				$msg = sprint("All whitelists are disbled, will not apply any filters, and be show all notifications.\n");
			} else {
				$msg = '';

				if ($nicklist == 0) { $msg .= "Nicks whitelist:    disabled\n"; }
				else { $msg .= "Nicks whitelist:    enabled\n"; }

				if ($chanlist == 0) { $msg .= "Channel whitelist:  disabled\n"; }
				else { $msg .= "Channel whitelist:  enabled\n"; }

				if ($netlist == 0) { $msg .= "Networks whitelist: disabled\n"; }
				else { $msg .= "Networks whitelist: enabled\n"; }
			}
		} elsif ($cmd eq 'enable') {
			if($entity eq 'nick') {
				if (defined(savesetting('nicklist', '1'))) {
					$msg = "Nicks whitelist now enabled\n";
				}
			} elsif ($entity eq 'chan') {
				if (defined(savesetting('chanlist', '1'))) {
					$msg = "Channel whitelist now enabled\n";
				}
			} elsif ($entity eq 'net') {
				if (defined(savesetting('netlist', '1'))) {
					$msg = "Networks whitelist now enabled\n";
				}
			}
		} elsif ($cmd eq 'disable') {
			if($entity eq 'nick') {
				if (defined(savesetting('nicklist', '0'))) {
					$msg = "Nicks whitelist now disabled\n";
				}
			} elsif ($entity eq 'chan') {
				if (defined(savesetting('chanlist', '0'))) {
					$msg = "Channel whitelist now disabled\n";
				}
			} elsif ($entity eq 'net') {
				if (defined(savesetting('netlist', '0'))) {
					$msg = "Networks whitelist now disabled\n";
				}
			}
		} elsif ($cmd eq 'show') {
			$msg = '';

			if (loadliststatus('nicklist') == 0) {
				$msg .= "Nicks whitelist:    disabled\n";
			} else {
				$msg .= "Nicks whitelist:    enabled\n";
			}

			$msg .= "Whitelisted nicks = " . join( ', ', loadlist('nicks')) ."\n";

			if (loadliststatus('chanlist') == 0) {
				$msg .= "Channel whitelist:  disabled\n";
			} else {
				$msg .= "Channel whitelist:  enabled\n";
			}

			$msg .= "Whitelisted channels = " . join( ', ', loadlist('chans')) . "\n";

			if (loadliststatus('netlist') == 0) {
				$msg .= "Networks whitelist: disabled\n";
			} else {
				$msg .= "Networks whitelist: enabled\n";
			}

			$msg .= "Whitelisted networks = " . join( ', ', loadlist('nets')) . "\n";
		} elsif ($cmd eq 'add') {
			if ((defined($entity)) and (defined($value))) {
				if ($entity eq 'nick') {
					my @nicks = (loadlist('nicks'), $value);

					unless (defined(savelist('nicks', @nicks))) {
						return HexChat::EAT_ALL;
					}

					$msg = sprintf("Nicks whitelist now: %s\n", join(', ', @nicks));
				} elsif ($entity eq 'chan') {
					my @chans = (loadlist('chans'), $value);

					unless (defined(savelist('chans', @chans))) {
						return HexChat::EAT_ALL;
					}

					$msg = sprintf("Channels whitelist now: %s\n", join(', ', @chans));
				} elsif ($entity eq 'net') {
					my @nets = (loadlist('nets'), $value);

					unless (defined(savelist('nets', @nets))) {
						return HexChat::EAT_ALL;
					}

					$msg = sprintf("Networks whitelist now: %s\n", join(', ', @nets));
				}
			}
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

					$msg = sprintf("Nicks whitelist now: %s\n", join(', ', @nicklist));
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

					$msg = sprintf("Channels whitelist now: %s\n", join(', ', @chanlist));
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

					$msg = sprintf("Networks whitelist now: %s\n", join(', ', @netlist));
				}
			}
		}
	}

	unless(defined($msg)){
		HexChat::print($help);
	} else {
		HexChat::print($msg);
	}

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

sub encodestr {
	my $str = shift;
	$str = join('', map {
		if ($_ eq '<') { $_ = '&lt;'; }
		elsif ($_ eq '>') { $_ = '&gt;'; }
		elsif ($_ eq '&') { $_ = '&amp;'; }
		elsif ($_ eq '"') { $_ = '&quot;'}
		else { $_ = $_; }
	} split(//, $str));

	return $str;
}
