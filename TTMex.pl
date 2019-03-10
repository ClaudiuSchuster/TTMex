#!perl
#-----------------------------------------------------
### Script-Name:   TTMex.pl
### Author:        Claudiu Schuster
### Website:       https://claudiuschuster.de
#-----------------------------------------------------

use strict; use warnings; use utf8; use feature ':5.10';
select(STDERR); $| = 1; select(STDOUT); $| = 1; # enable autoflush

use LWP;
use Date::Format;
use Config::Tiny;
use Scalar::Util qw(looks_like_number);
use JSON::PP qw(decode_json);
use Digest::SHA qw(hmac_sha256_hex); 
use HTTP::Date qw(str2time);



#### Config #####
my $Config                     = Config::Tiny->new;
$Config                        = Config::Tiny->read( 'TTMex.cfg' );
my $apiKey                     = $Config->{_}->{apiKey};
my $apiSecret                  = $Config->{_}->{apiSecret};
my $data_startTime             = $Config->{_}->{data_startTime};
my $profitsFilename            = $Config->{_}->{profitsFilename};
my $requestExpireSec           = $Config->{_}->{requestExpireSec};
my $maxFailsBeforeDisplayError = $Config->{_}->{maxFailsBeforeDisplayError};
my $minimumSleep               = $Config->{_}->{minimumSleep};


#### SUBS #####
sub getData {
    my $query = shift;
    my $url       = 'https://www.bitmex.com';
    my $expires   = time + $requestExpireSec;
    
    my $req = HTTP::Request->new( 'GET', $url.$query );
    $req->header(
        'Accept'           => 'application/json',
        'X-Requested-With' => 'XMLHttpRequest',
        'api-expires'      => $expires,
        'api-key'          => $apiKey,
        'api-signature'    => hmac_sha256_hex('GET'.$query.$expires, $apiSecret)
    );
    my $lwp = LWP::UserAgent->new;
    return $lwp->request( $req );
}


#### MAIN #####
system("mode con lines=40 cols=148"); system("cls"); print "Loading data...\n";
my $fails = 0;
while (1) {
    my $screenOutput = '';
    
  #### walletHistory #####
    print ".";
    my $res = getData('/api/v1/user/walletHistory?currency=XBt&count=999999999');
    my @data;
    eval { @data = @{decode_json($res->content)};  1; } or do { 
        if( $fails > $maxFailsBeforeDisplayError ){ system("cls"); print "Error fetching data for $fails times! - retry in 1 sec...\n"; } else { print "."; }
        $fails++; sleep 1; redo;
    };

    $data_startTime = str2time($data_startTime) unless looks_like_number($data_startTime);
    for (reverse 0 .. $#data) {    # Remove elements before $data_startTime and set unix timestamp
        if( defined $data[$_]->{timestamp} ) {
            $data[$_]->{timestamp} = str2time($data[$_]->{timestamp});
            splice(@data, $_, 1) if( $data[$_]->{timestamp} < $data_startTime);
        } else {
            $data[$_]->{timestamp} = time;
        }
    }
    pop(@data);

    my ($amountTotal,$amount1M,$amount1W,$amount3d,$amount2d,$amount1d) = (0,0,0,0,0,0);
    for (reverse @data) {
        if( $_->{transactType} =~ /RealisedPNL|UnrealisedPNL|AffiliatePayout/ ) {
            $amountTotal += $_->{amount};
            $amount1M    += $_->{amount} if( $_->{timestamp} >= time - 86400*30.436875 );
            $amount1W    += $_->{amount} if( $_->{timestamp} >= time - 86400*7 );
            $amount3d    += $_->{amount} if( $_->{timestamp} >= time - 86400*3 );
            $amount2d    += $_->{amount} if( $_->{timestamp} >= time - 86400*2 );
            $amount1d    += $_->{amount} if( $_->{timestamp} >= time - 86400 );
        }
    }
    
    my $profits = "Total: ".sprintf("%+.2f", $amountTotal/10**8)
                  ."    1M: ".sprintf("%+.2f", $amount1M/10**8)
                  ."    1W: ".sprintf("%+.2f", $amount1W/10**8)
                  ."    3D: ".sprintf("%+.2f", $amount3d/10**8)
                  ."    2D: ".sprintf("%+.2f", $amount2d/10**8)
                  ."    1D: ".sprintf("%+.4f", $amount1d/10**8)
                  ."\n";
    $screenOutput .= "==== Profits "; $screenOutput .= '=' x 134;
    $screenOutput .= "\n $profits";
    
    if( $profitsFilename ) {
        open(my $fh, '>', $profitsFilename) or die "Could not open file '$profitsFilename' for writing: $!";
        print $fh $profits;
        close $fh;
    }
    
    print ".|";
    
    
  #### Positions #####
    print ".";
    $res = getData('/api/v1/position?columns=%5B%22avgEntryPrice%22%2C%22unrealisedPnl%22%2C%22realisedPnl%22%2C%22markPrice%22%2C%22currentQty%22%5D');
    eval { @data = @{decode_json($res->content)};  1; } or do { 
        if( $fails > $maxFailsBeforeDisplayError ){ system("cls"); print "Error fetching data for $fails times! - retry in 1 sec...\n"; } else { print "."; }
        $fails++; sleep 1; redo;
    };
    
    $screenOutput .= "\n\n==== Positions "; $screenOutput .= '=' x 132;
    for (@data) {
        $screenOutput .= "\n ".$_->{symbol}."\t   Size: ".sprintf("%-8s", $_->{currentQty})
                      ."\tEntry: ".( $_->{avgEntryPrice} < 0.001 ? sprintf("%.8f", $_->{avgEntryPrice}) : sprintf("%-10s", $_->{avgEntryPrice}) )
                      ."\tMark: ".( $_->{markPrice} < 0.001 ? sprintf("%.8f", $_->{markPrice}) : sprintf("%-10s", $_->{markPrice}) )
                      ."\tLiq: ".( $_->{liquidationPrice} < 0.001 ? $_->{liquidationPrice} == 0 ? sprintf("%-10s", 0) : sprintf("%.8f", $_->{liquidationPrice}) : sprintf("%-10s", $_->{liquidationPrice}) )
                      ." \tU-PNL: ".sprintf("%+.4f", $_->{unrealisedPnl}/10**8)
                      ."\t\tR-PNL: ".sprintf("%+.4f", $_->{realisedPnl}/10**8)
                      ."\n" if( defined $_->{avgEntryPrice} );
    }
    
    print ".|";
    
    
  #### Active Orders #####
    print ".";
    $res = getData('/api/v1/order?filter=%7B%22ordStatus%22%3A%20%22New%22%7D&reverse=false');
    eval { @data = @{decode_json($res->content)};  1; } or do { 
        if( $fails > $maxFailsBeforeDisplayError ){ system("cls"); print "Error fetching data for $fails times! - retry in 1 sec...\n"; } else { print "."; }
        $fails++; sleep 1; redo;
    };
    
    $screenOutput .= "\n\n==== Active Orders "; $screenOutput .= '=' x 128;
    for (@data) { # ["symbol","side","orderQty","leavesQty","cumQty","price","ordType","execInst"] # execInst=ReduceOnly
        $screenOutput .= "\n ".$_->{symbol}."\t   ".sprintf("%4s", uc($_->{side})).": ".sprintf("%-8s", $_->{orderQty})
                      ."\tPrice: ".( $_->{price} < 0.001 ? sprintf("%.8f", $_->{price}) : sprintf("%-10s", $_->{price}) )
                      ." \tLeaves: ".sprintf("%-10s", $_->{leavesQty})
                      ." \tCum: ".sprintf("%-10s", $_->{cumQty})
                      ."\tType: ".sprintf("%-10s", $_->{ordType})
                      ."\tExecInst: ".$_->{execInst}
                      ."\n";
    }
    
    print ".|";

    
  #############  PRINT CONSOLE #################
    system("cls");
    print $screenOutput."\n\n";
    
    
  ######## Sleeping/Ratelimit/FailReset ########
    $fails = 0;
    my $rateLimit = $res->headers->{'x-ratelimit-limit'}."\n";
    my $rateLimitRemaining = $res->headers->{'x-ratelimit-remaining'}."\n";
    my $refresh = $rateLimit - $rateLimitRemaining >= $minimumSleep ? $rateLimit - $rateLimitRemaining : $minimumSleep;
    my $lastUpdate = "| ".time2str("%Y/%m/%d - %X", time)." |.|";
    print "\n\n$lastUpdate";
    for (0 .. $refresh) {
        chop($lastUpdate);
        $lastUpdate .= ".|";
        sleep 1;
        print "\r" . " " x 140 . "\r$lastUpdate";
    }
}


1;