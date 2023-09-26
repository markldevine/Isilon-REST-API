#!/usr/bin/env raku

use lib '/home/mdevine/github.com/raku-REST-Client-Role/lib';
use REST::Client;
use Cro::Uri;

use Data::Dump::Tree;

my $user-id         =   'WMATA\tsmadmin';
my $user-id-sterile = $user-id.subst('\\', '_');

my @nfs-queries     =   'https://jgctnfs.wmataisln.local:8080/platform/1/protocols/nfs/exports';
#                       'https://jgctsmb.wmataisln.local:8080/platform/1/protocols/nfs/exports';

my @smb-queries     =   'https://jgctsmb.wmataisln.local:8080/platform/1/protocols/smb/shares',
                        'https://vdismb.wmataisln.local:8080/platform/1/protocols/smb/shares';
#                       'https://jgctnfs.wmataisln.local:8080/platform/1/protocols/smb/shares';

class Isilon-Rest-Client does REST::Client {}

my $stash-path;

sub MAIN (
#   Str:D   :$url!,                                 #= full URL string
#   Str:D   :$user-id,                              #= user id for authentication
    Bool    :$nfs,                                  #= list NFS shares
    Bool    :$smb,                                  #= list SMB shares
    ) {
    my $rest-client;
    if $nfs {
        for @nfs-queries -> $url {
            my $user-id-sterile = $user-id.subst('\\', '_');
            $stash-path = $*HOME ~ '/.' ~ $*PROGRAM-NAME.IO.basename ~ '/servers/' ~ Cro::Uri.parse($url).host ~ '/' ~ $user-id-sterile ~ '.khph';
            $rest-client    = Isilon-Rest-Client.new(:$url, :$user-id, :insecure, :$stash-path,);
            my $body        = $rest-client.get;
            for $body<exports>.list -> $export {
                for $export<paths>.list -> $path {
                    printf "%s\n", $path;
                }
            }
        }
    }
    elsif $smb {
        for @smb-queries -> $url {
            $stash-path = $*HOME ~ '/.' ~ $*PROGRAM-NAME.IO.basename ~ '/servers/' ~ Cro::Uri.parse($url).host ~ '/' ~ $user-id-sterile ~ '.khph';
            $rest-client    = Isilon-Rest-Client.new(:$url, :$user-id, :insecure, :$stash-path,);
            my $body        = $rest-client.get;
            for $body<shares>.list -> $share {
                printf "%-30s%s\n", $share<name>, $share<path>;
            }
        }
    }
    else {
        die $*USAGE;
    }
}

=finish

curl https://jgctnfs.wmataisln.local:8080/platform/1/protocols/smb/shares --insecure --basic --user wmata\\tsmadmin:${PASSWD}
curl https://jgctnfs.wmataisln.local:8080/platform/1/protocols/nfs/exports --insecure --basic --user wmata\\tsmadmin:${PASSWD}
curl https://jgctsmb.wmataisln.local:8080/platform/1/protocols/smb/shares --insecure --basic --user wmata\\tsmadmin:${PASSWD}
curl https://jgctsmb.wmataisln.local:8080/platform/1/protocols/nfs/exports --insecure --basic --user wmata\\tsmadmin:${PASSWD}
curl https://vdismb.wmataisln.local:8080/platform/1/protocols/smb/shares --insecure --basic --user wmata\\tsmadmin:${PASSWD}
#curl https://vdismb.wmataisln.local:8080/platform/1/protocols/nfs/exports --insecure --basic --user wmata\\tsmadmin:${PASSWD}
