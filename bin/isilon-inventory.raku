#!/usr/bin/env raku

#use lib '/home/mdevine/github.com/raku-REST-Client-Role/lib';
use ISP::dsmadmc;
use REST::Client;

use Data::Dump::Tree;

#   KEYS
#   ----
#   eb:isilon:nfs:authorities
#   eb:isilon:smb:authorities
#   eb:isilon:service-account

sub get-config {
    my @redis-servers;
    if "$*HOME/.redis-servers".IO.f {
        @redis-servers = slurp("$*HOME/.redis-servers").chomp.split("\n");
    }
    else {
        die 'Unable to initialized without ~/.redis-servers';
    }
    my @redis-clis;
    for @redis-servers -> $redis-server {
        my @cmd-string = sprintf("ssh -L 127.0.0.1:6379:%s:6379 %s /usr/bin/redis-cli", $redis-server, $redis-server).split: /\s+/;
        @redis-clis.push: @cmd-string;
    }
#   for @redis-clis -> @redis-cli {
#       my @rcmd        = flat @redis-cli,
#                       '--raw',
#                       'KEYS',
#                       $isp-server-REDIS-keys-base ~ ':*';
#       my $proc        = run   @rcmd, :out, :err;
#       my $out         = $proc.out.slurp(:close);
#       my $err         = $proc.err.slurp(:close);
#       fail 'FAILED: ' ~ @rcmd ~ ":\t" ~ $err if $err;
#       if $out {
#           my @ispssks = $out.chomp.split("\n");
#           die "No ISP server site keys!" unless @ispssks;
#           @rcmd   = flat @redis-cli,
#                   '--raw',
#                   'SUNION',
#                   @ispssks.join: ' ';
#           $proc    = run   @rcmd, :out, :err;
#           $out     = $proc.out.slurp(:close);
#           $err     = $proc.err.slurp(:close);
#           die 'FAILED: ' ~ @rcmd ~ ":\t" ~ $err if $err;
#           if $out {
#               %!isp-servers = $out.chomp.split("\n").map: { $_.uc => {} };
#               die "Set up '/opt/tivoli/tsm/client/ba/bin/dsm.sys' & install '/usr/bin/dsmadmc' on this host." unless '/opt/tivoli/tsm/client/ba/bin/dsm.sys'.IO.path:s;
#               my @dsm-sys     = slurp('/opt/tivoli/tsm/client/ba/bin/dsm.sys').lines;
#               my $current-server;
#               my $current-client;
#               for @dsm-sys -> $rcd {
#                   if $rcd ~~ m:i/ ^ SERVERNAME \s+ $<client>=(<alnum>+?) '_' $<server>=(<alnum>+) \s* $ / {           # %%% make this accept client names with '_'; take all but not the last '_'
#                       $current-server = $/<server>.Str;
#                       $current-client = $/<client>.Str;
#                       %!isp-servers{$current-server}{$current-client} = ISP-SERVER-INFO.new(:SERVERNAME($current-client ~ '_' ~ $current-server));
#                   }
#                   elsif $rcd ~~ m:i/ ^ \s* TCPS\w* \s+ $<value>=(.+) \s* $/ {
#                       %!isp-servers{$current-server}{$current-client}.TCPSERVERADDRESS = $/<value>.Str;
#                   }
#               }
#               return self;
#           }
#       }
#   }
#   unless %!isp-servers.elems {
#       $*ERR.put: colored('No ISP Servers defined in Redis under ' ~ $isp-server-REDIS-keys-base ~ ' keys!', 'red');
#       die colored('Either fix your --$isp-server=<value> or update Redis ' ~ $isp-server-REDIS-keys-base ~ ':*', 'red');
#   }
}

my $user-id         =   'WMATA\tsmadmin';
my $user-id-sterile = $user-id.subst('\\', '_');

my @nfs-authorities =   'jgctnfs.wmataisln.local:8080',
                        'jgdciisln01nfs.wmataisln.local:8080',
                        'ctdciisln01nfs.wmataisln.local:8080';

my @smb-authorities =   'jgctsmb.wmataisln.local:8080',
                        'jgdciisln01nfs.wmataisln.local:8080',
                        'ctdciisln01nfs.wmataisln.local:8080',
                        'vdismb.wmataisln.local:8080';

class Isilon-Rest-Client does REST::Client {}

my $stash-path;

sub MAIN (
    Str:D   :$isp-server!,                      #= ISP server name (SELECT SERVER_NAME FROM STATUS)
    Str:D   :$isp-admin!,                       #= ISP server Admin account
    Bool    :$nfs,                              #= list NFS shares
    Bool    :$smb,                              #= list SMB shares
    ) {
    get-config();
    my $rest-client;

    my ISP::dsmadmc $dsmadmc   .= new(:$isp-server, :$isp-admin);

    if $nfs {
        my %isp-nodes;
        my %isilon-paths;
        for $dsmadmc.execute(['SELECT', 'NODE_NAME', 'FROM', 'NODES', 'WHERE', 'NODEGROUP', 'LIKE', "'%NFS%'"]) -> $node-record {
            %isp-nodes{$node-record<NODE_NAME>} = '?';
        }
        for @nfs-authorities -> $authority {
            $stash-path         = $*HOME ~ '/.' ~ $*PROGRAM-NAME.IO.basename ~ '/servers/' ~ $authority ~ '/' ~ $user-id-sterile ~ '.khph';
            $rest-client        = Isilon-Rest-Client.new(:url('https://' ~ $authority ~ '/platform/1/protocols/nfs/exports'), :$user-id, :insecure, :$stash-path,);
            my $body            = $rest-client.get;
            for $body<exports>.list -> $export {
                for $export<paths>.list -> $path {
                    %isilon-paths{$path} = '?';
                    my $prefix  = '?_';
                    if $path ~~ /^ \/ifs\/j / {
                        $prefix = 'P_';
                    }
                    elsif $path ~~ /^ \/ifs\/c / {
                        $prefix = 'C_';
                    }
                    else {
                        die "?_" ~ $path.IO.basename.uc;
                    }
                    if %isp-nodes{$prefix ~ $path.IO.basename.uc}:exists {
                        %isp-nodes{$prefix ~ $path.IO.basename.uc}  = $path;
                        %isilon-paths{$path}                        = $prefix ~ $path.IO.basename.uc;
                    }
                }
            }
        }
        my @no-rest-presence;
        for %isp-nodes.kv -> $node, $value {
             @no-rest-presence.push: $node if $value eq '?';
        }
        if @no-rest-presence {
            put "The following registered ISP NFS node(s) were not listed in the REST responses:\n";
            .put for @no-rest-presence;
        }
        my @no-node-registered;
        for %isilon-paths.kv -> $path, $value {
             @no-node-registered.push: $path if $value eq '?';
        }
        if @no-node-registered {
            put '' if @no-rest-presence.elems;
            put "The following NFS exports(s) do not have a registered ISP node:\n";
            .put for @no-node-registered;
        }
    }
    elsif $smb {
        my %isp-nodes;
        my %isilon-shares;
        for $dsmadmc.execute(['SELECT', 'NODE_NAME', 'FROM', 'NODES', 'WHERE', 'NODEGROUP', 'LIKE', "'%SMB%'"]) -> $node-record {
            %isp-nodes{$node-record<NODE_NAME>} = '?';
        }
        for @smb-authorities -> $authority {
            $stash-path = $*HOME ~ '/.' ~ $*PROGRAM-NAME.IO.basename ~ '/servers/' ~ $authority ~ '/' ~ $user-id-sterile ~ '.khph';
            $rest-client    = Isilon-Rest-Client.new(:url('https://' ~ $authority ~ '/platform/1/protocols/smb/shares'), :$user-id, :insecure, :$stash-path,);
            my $body        = $rest-client.get;
            for $body<shares>.list -> $share {
                %isilon-shares{$share<name>} = '?';
                my $prefix  = 'SMB_';
                if %isp-nodes{$prefix ~ $share<name>.uc}:exists {
                    %isp-nodes{$prefix ~ $share<name>.uc}   = $share<path>;
                    %isilon-shares{$share<name>.uc}         = $prefix ~ $share<name>.uc;
                }
            }
        }
        my @no-rest-presence;
        for %isp-nodes.kv -> $node, $value {
             @no-rest-presence.push: $node if $value eq '?';
        }
        if @no-rest-presence {
            put "The following registered ISP SMB node(s) were not listed in the REST responses:\n";
            .put for @no-rest-presence;
        }
        my @no-node-registered;
        for %isilon-shares.kv -> $share, $value {
             @no-node-registered.push: $share if $value eq '?';
        }
        if @no-node-registered {
            put '' if @no-rest-presence.elems;
            put "The following SMB share(s) do not have a registered ISP node:\n";
            .put for @no-node-registered;
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


#!/usr/bin/bash

cd /var/ansible/code/redis

### Sets
for FGSTLCSETKEY in `/usr/bin/redis-cli --raw keys fg:st:lc:*`
do
    /usr/bin/redis-cli DEL $FGSTLCSETKEY
done
/usr/bin/awk -F, '$1 ~ /^\w/ {print "SADD", "fg:st:lc:"$1, $2}' ./SOURCE/fg-st-lc.csv | /usr/bin/redis-cli --pipe
/usr/bin/redis-cli SUNIONSTORE fg:st:lc:all fg:st:lc:dev fg:st:lc:tst fg:st:lc:qa fg:st:lc:prd

### Strings
for FGSTLCSTRINGKEY in `/usr/bin/redis-cli --raw keys fg-st-lc*`
do
    /usr/bin/redis-cli DEL $FGSTLCSTRINGKEY
done
/usr/bin/redis-cli SET fg-st-lc-dev "`/usr/bin/redis-cli --raw SMEMBERS fg:st:lc:dev | /usr/bin/sort -f | tr [:lower:] [:upper:]`"
/usr/bin/redis-cli SET fg-st-lc-qa  "`/usr/bin/redis-cli --raw SMEMBERS fg:st:lc:qa  | /usr/bin/sort -f | tr [:lower:] [:upper:]`"
/usr/bin/redis-cli SET fg-st-lc-tst "`/usr/bin/redis-cli --raw SMEMBERS fg:st:lc:tst | /usr/bin/sort -f | tr [:lower:] [:upper:]`"
/usr/bin/redis-cli SET fg-st-lc-prd "`/usr/bin/redis-cli --raw SMEMBERS fg:st:lc:prd | /usr/bin/sort -f | tr [:lower:] [:upper:]`"
/usr/bin/redis-cli SET fg-st-lc-all "`/usr/bin/redis-cli --raw SMEMBERS fg:st:lc:all | /usr/bin/sort -f | tr [:lower:] [:upper:]`"
