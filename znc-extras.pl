#!/usr/bin/perl

my $ShowMode = "mode \00310%s\003 \002%s\002 by \002%s\002";
my $ModName = "*savebuff";

Xchat::register('ZNC-Buffer','1.00','Display the on-join buffer for ZNC nicely', \&freehook);

my @hooks;
push @hooks, Xchat::hook_server('PRIVMSG',\&ProcessPMSG);
push @hooks, Xchat::hook_server('MODE',\&ShowModes);
push @hooks, Xchat::hook_print('Channel Operator',\&DontDisplay);
push @hooks, Xchat::hook_print('Channel DeOp',\&DontDisplay);
push @hooks, Xchat::hook_print('Channel Voice',\&DontDisplay);
push @hooks, Xchat::hook_print('Channel DeVoice',\&DontDisplay);
push @hooks, Xchat::hook_print('Channel Ban',\&DontDisplay);
push @hooks, Xchat::hook_print('Channel UnBan',\&DontDisplay);
push @hooks, Xchat::hook_print('Channel Mode Generic',\&DontDisplay);
push @hooks, Xchat::hook_print('Channel Set Key',\&DontDisplay);
push @hooks, Xchat::hook_print('Channel Set Limit',\&DontDisplay);
push @hooks, Xchat::hook_print('Channel Remove Keyword',\&DontDisplay);
push @hooks, Xchat::hook_print('Channel Remove Limit',\&DontDisplay);

sub ShowMode {
        my ($Channel,$Modes,$Nick) = @_;

        my $Output = sprintf($ShowMode,$Channel,$Modes,$Nick);
        Xchat::emit_print("Generic Message","-\00310-\002-\002\003",$Output,null);
}

sub ProcessPMSG {
        my @Word = @{$_[0]};
        my @Word_EOL = @{$_[1]};
        if ((substr($Word[0],1,length($ModName)) eq $ModName) && ($Word[3]) && ($Word[4]) && ($Word[5])) {
                my $Channel = $Word[2];
                my $Hostmask = $Word[4];
                my $Type = $Word[5];
                my $Args = ($Word[6]) ? $Word_EOL[6] : undef;

                my ($Nick, $Host) = ($Hostmask =~ /^([^\!]+)!(.+)$/g);

                if ($Type eq 'MODE') {
                       ShowMode($Channel,$Args,$Nick);
                } elsif ($Type eq 'JOIN') {
                        Xchat::emit_print("Join",$Nick,$Channel,$Host,null);
                } elsif ($Type eq 'PART') {
                        Xchat::emit_print("Part",$Nick,$Host,$Channel,null);
                } elsif ($Type eq 'NICK') {
                        if ($Args) {
                                Xchat::emit_print("Change Nick",$Nick,$Args,null);
                        } else {
                                Xchat::emit_print("Change Nick",$Nick,"*shrug*",null);
                        }
                } elsif ($Type eq 'QUIT') {
                        if ($Args) {
                                Xchat::emit_print("Quit",$Nick,$Args,null);
                        } else {
                                Xchat::emit_print("Quit",$Nick,"No Reason",null);
                        }
                } elsif ($Type eq 'KICK') {
                        my ($bNick,$bHost) = ($Word[6] =~ /^([^\!]+)!(.+)$/g);

                        if ($Word[7]) {
                                Xchat::emit_print("Kick",$bNick,$Nick,$Channel,$Word_EOL[7],null);
                        } else {
                                Xchat::emit_print("Kick",$bNick,$Nick,$Channel,"No Reason",null);
                        }
                } else {
                        printf STDERR "Unhandled Text! [%s]\n", $Word_EOL[3];
                }

                return Xchat::EAT_ALL;
        }

        return Xchat::EAT_NONE;
}

sub DontDisplay {
        return Xchat::EAT_XCHAT;
}

sub ShowModes {
        my @Word = @{$_[0]};
        my @Word_EOL = @{$_[1]};

        my $Channel = $Word[2];
        $Word[0] =~ /^:([^\!]+)!.*/;
        $Nick = $1;
        my $Modes = $Word_EOL[3];

        ShowMode($Channel,$Modes,$Nick);

        return Xchat::EAT_NONE; 
}

sub freehooks {
	foreach (@hooks) {
		HexChat::unhook($_);
	}

	return HexChat::EAT_ALL;
}
