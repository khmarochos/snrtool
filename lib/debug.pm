# 
#   debug.pm, Yet another high-level logging library (I wrote it just
#   for myself only, so don't ask anything about it).
#   Copyright (C) 2001  V.Melnik <melnik@raccoon.kiev.ua>
#
#   This library is free software; you can redistribute it and/or
#   modify it under the terms of the GNU Lesser General Public
#   License as published by the Free Software Foundation; either
#   version 2.1 of the License, or (at your option) any later version.
#
#   This library is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#   Lesser General Public License for more details.
#
#   You should have received a copy of the GNU Lesser General Public
#   License along with this library; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#

package debug;

use strict;

use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

my @debug_levels = qw(
    DEBUG_QUIET DEBUG_ERRORS DEBUG_WARNINGS
    DEBUG_EVENTS DEBUG_NOTES DEBUG_ACTIONS
);

$VERSION            = '0.40';
@ISA                = qw(Exporter);
@EXPORT             = qw();
@EXPORT_OK          = @debug_levels;
%EXPORT_TAGS        = (debug_levels => [@debug_levels]);

# Get some FRESH SHIT!
sub DEBUG_QUIET()       { 0 };
sub DEBUG_ERRORS()      { 1 };
sub DEBUG_WARNINGS()    { 2 };
sub DEBUG_EVENTS()      { 3 };
sub DEBUG_NOTES()       { 4 };
sub DEBUG_ACTIONS()     { 5 };

# "I need you, I need you, I neeeeeeeeeeeeeeeeeeeeed you..."
use Unix::Syslog qw(:subs);
use Unix::Syslog qw(:macros);
use POSIX qw(strftime);

my $now = strftime("%H:%M:%S %Y-%m-%d", localtime);

# Constructing constructor constructed constructor... %-\
sub new {
    my($class, %argv) = @_;
    my $self = {
        debug_level         => undef,
        logfile             => undef,
        logfile_fh          => undef,
        syslog_ident        => undef,
        syslog_option       => undef,
        syslog_facility     => undef,
        error               => undef
    };
    # "God bless you, son!.."
    bless($self, $class);
    # "What do you want from me?"
    foreach (keys(%argv)) {
        if (/^-?debug_level$/i) {
            $self->{'debug_level'}      = $argv{$_};
        } elsif (/^-?logfile$/i) {
            $self->{'logfile'}          = $argv{$_};
        } elsif (/^-?syslog_ident$/i) {
            $self->{'syslog_ident'}     = $argv{$_};
        } elsif (/^-?syslog_option$/i) {
            $self->{'syslog_option'}    = $argv{$_};
        } elsif (/^-?syslog_facility$/i) {
            $self->{'syslog_facility'}  = $argv{$_};
        } else {
            return(undef, "Unknown parameter $_");
        }
    }
    # Open >>LOGFILE
    if ($self->{'logfile'}) {
        unless (open(logfile_fh, ">>$self->{'logfile'}")) {
            return(undef, "Can't write to $self->{'logfile'}");
        }
        $self->{'logfile_fh'} = \*logfile_fh;
    }
    # Do you want to able syslogging?
    if (
        $self->{'syslog_ident'} or
        $self->{'syslog_option'} or
        $self->{'syslog_facility'}
    ) {
        $self->{'syslog_ident'}     = $0
            unless(defined($self->{'syslog_ident'}));
        $self->{'syslog_option'}    = LOG_PID
            unless(defined($self->{'syslog_option'}));
        $self->{'syslog_facility'}  = LOG_USER
            unless(defined($self->{'syslog_facility'}));
        openlog(
            $self->{'syslog_ident'},
            $self->{'syslog_option'},
            $self->{'syslog_facility'}
        );
    }
    $self->write(DEBUG_ACTIONS, "--- Loggers opened, returning object-reference ---");
    return($self);
}

# Messanger;
sub write {
    my $self = shift;
    my($debug_level, @message) = @_;
    my $old_AF = $|;
    $| = 1;
    if ($debug_level <= $self->{'debug_level'}) {
        if(@message > 0) {
            my $priority;
            my $logfile_fh = $self->{'logfile_fh'};
            CHOOSE_DL: {
                if ($debug_level == DEBUG_ERRORS) {
                    $priority = LOG_ERR;
                    unshift(@message, "[ERR]");
                    print($logfile_fh "$now pid:$$ @message\n") if ($self->{'logfile'});
                    last CHOOSE_DL;
                } elsif ($debug_level == DEBUG_WARNINGS) {
                    $priority = LOG_WARNING;
                    unshift(@message, "[WRN]");
                    print($logfile_fh "$now pid:$$ @message\n") if ($self->{'logfile'});
                    last CHOOSE_DL;
                } elsif ($debug_level == DEBUG_EVENTS) {
                    $priority = LOG_NOTICE;
                    unshift(@message, "[EVT]");
                    print($logfile_fh "$now pid:$$ @message\n") if ($self->{'logfile'});
                    last CHOOSE_DL;
                } elsif ($debug_level == DEBUG_NOTES) {
                    $priority = LOG_INFO;
                    unshift(@message, "[NTS]");
                    print($logfile_fh "$now pid:$$ @message\n") if ($self->{'logfile'});
                    last CHOOSE_DL;
                } elsif ($debug_level == DEBUG_ACTIONS) {
                    $priority = LOG_DEBUG;
                    unshift(@message, "[ACT]");
                    print($logfile_fh "$now pid:$$ @message\n") if ($self->{'logfile'});
                    last CHOOSE_DL;
                } else {
                    $priority = LOG_CRIT;
                    unshift(@message, "[?!?]");
                    print($logfile_fh "$now pid:$$ @message\n") if ($self->{'logfile'});
                    last CHOOSE_DL;
                }
            }
            # Do you want syslogging?
            if (
                $self->{'syslog_ident'} or
                $self->{'syslog_option'} or
                $self->{'syslog_facility'}
            ) {
                syslog($priority, "@message");
            }
        } else {
            $self->{'error'} = "Supplied message is empty";
            return(undef);
        }
    }
    $| = $old_AF;
    return;
}

# "Close your eyes, close your eyes..." |-O
sub close {
    my $self = shift;
    # Close LOGFILE
    if ($self->{'logfile'}) {
        $self->write(DEBUG_ACTIONS, "--- Closing file-logger, bye-bye! ---");
        close($self->{'logfile_fh'});
        $self->{'logfile'} = undef;
    }
    # Syslogged? Shut up!
    if (
        defined($self->{'syslog_ident'}) or
        defined($self->{'syslog_option'}) or
        defined($self->{'syslog_facility'})
    ) {
        $self->write(DEBUG_ACTIONS, "--- Closing syslog-logger, bye-bye! ---");
        closelog;
        $self->{'syslog_ident'}     = undef;
        $self->{'syslog_option'}    = undef;
        $self->{'syslog_facility'}  = undef;
    }
}

sub DESTROY {
    my $self = shift;
    $self->close();
}

1;
