# 
#   snr, Collects, stores and shows SNR for Lucent AcessPoint devices.
#   Copyright (C) 2001  V.Melnik <melnik@raccoon.kiev.ua>
#
#   NOTE: This is not a standalone library, it's just a module!
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#

package snr::config;

use strict;

use Exporter;
use vars qw(@ISA @EXPORT $VERSION);

@ISA            = qw(Exporter);
@EXPORT         = qw($VERSION);

$VERSION        = '0.98';

1;

