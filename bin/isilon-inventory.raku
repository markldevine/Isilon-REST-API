#!/usr/bin/env raku

use lib '/home/mdevine/github.com/raku-REST-Client-Role/lib';
use ISP::dsmadmc;
use REST::Client;
use Cro::Uri;

use Data::Dump::Tree;

my $user-id         =   'WMATA\tsmadmin';
my $user-id-sterile = $user-id.subst('\\', '_');

my @nfs-queries     =   'https://jgctnfs.wmataisln.local:8080/platform/1/protocols/nfs/exports',
                        'https://jgdciisln01nfs.wmataisln.local:8080/platform/1/protocols/nfs/exports',
                        'https://ctdciisln01nfs.wmataisln.local:8080/platform/1/protocols/nfs/exports';

my @smb-queries     =   'https://jgctsmb.wmataisln.local:8080/platform/1/protocols/smb/shares',
                        'https://vdismb.wmataisln.local:8080/platform/1/protocols/smb/shares';
#                       'https://jgctnfs.wmataisln.local:8080/platform/1/protocols/smb/shares';

class Isilon-Rest-Client does REST::Client {}

my $stash-path;

sub MAIN (
    Str:D   :$isp-server!,                      #= ISP server name (SELECT SERVER_NAME FROM STATUS)
    Str:D   :$isp-admin!,                       #= ISP server Admin account
    Bool    :$nfs,                              #= list NFS shares
    Bool    :$smb,                              #= list SMB shares
    ) {
    my $rest-client;

    my ISP::dsmadmc $dsmadmc   .= new(:$isp-server, :$isp-admin);

    if $nfs {
        my %nfs-nodes;
        for $dsmadmc.execute(['SELECT', 'NODE_NAME', 'FROM', 'NODES', 'WHERE', 'NODEGROUP', 'LIKE', "'%NFS%'"]) -> $node-record {
            %nfs-nodes{$node-record<NODE_NAME>} = 1;
        }
#ddt %nfs-nodes;
#die;
        for @nfs-queries -> $url {
            my $user-id-sterile = $user-id.subst('\\', '_');
            $stash-path = $*HOME ~ '/.' ~ $*PROGRAM-NAME.IO.basename ~ '/servers/' ~ Cro::Uri.parse($url).host ~ '/' ~ $user-id-sterile ~ '.khph';
            $rest-client    = Isilon-Rest-Client.new(:$url, :$user-id, :insecure, :$stash-path,);
            my $body        = $rest-client.get;
            for $body<exports>.list -> $export {
                for $export<paths>.list -> $path {
                    printf "%s", $path;
                    if $path ~~ /^ \/ifs\/j / {
                        put "\tP_";
                    }
                }
            }
        }
    }
    elsif $smb {
        for $dsmadmc.execute(['SELECT', 'NODE_NAME', 'FROM', 'NODES', 'WHERE', 'NODEGROUP', 'LIKE', "'%SMB%'"]) -> $node-record {
            put $node-record<NODE_NAME>;
        }
die;
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
