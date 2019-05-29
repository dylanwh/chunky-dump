#/usr/bin/env perl

use 5.28.0;
use Mojolicious;
use IO::Socket::SSL;
use IO::Socket::INET;
use Mojo::Util qw(md5_sum b64_encode gunzip getopt);
use Mojo::URL;
use JSON::MaybeXS;

my $url_opt = "https://bug1544298.bmoattachments.org/attachment.cgi?id=9058642";
my $connect;
my $verbose = 0;
my $proxy   = 0;
my $use_ssl = 1;

getopt
  'url|u=s'     => \$url_opt,
  'connect|c=s' => \$connect,
  'verbose|v'   => \$verbose,
  'proxy|p'     => \$proxy;

my $url = Mojo::URL->new($url_opt);
$url->port(443) if $url->scheme eq 'https';

$use_ssl = 0 if $connect;
$connect //= $url->host_port;

my $get_request = <<REQUEST;
GET @{[ $url->path_query ]} HTTP/1.1
Accept: */*
Accept-Encoding: gzip, deflate
Host: @{[ $url->host ]}
User-Agent: $0
Connection: keep-alive
REQUEST

my $socket;
if ($use_ssl) {
  $socket = IO::Socket::SSL->new($connect);
}
else {
  $socket = IO::Socket::INET->new($connect);
  $get_request .= "X-Forwarded-Proto: https\n";
  $get_request .= "X-Forwarded-For: 72.187.223.97\n";
}

die "cannot connect to $connect: $!" unless $socket;

my $first = submit($socket, $get_request);

my $json = JSON::MaybeXS->new(pretty => 1, canonical => 1);
say $json->encode($first);

sub submit {
  my ($socket, $request) = @_;
  $socket->print($request =~ s/\n/\r\n/gsr . "\r\n");

  my $header    = '';
  my $content   = '';
  my $in_header = 1;
  my $chunked   = 0;
  my $content_length;
  my @chunks;

  $SIG{ALRM} = sub { die "Timeout exceeded!" };
  alarm(240);
  my $ok = eval {
    while (my $line = $socket->getline) {
      if ($in_header) {
        if ($line eq "\r\n") {
          $in_header = 0;
          if (!$chunked && defined $content_length) {
            $socket->read($content, $content_length);
            last;
          }
          elsif (!$chunked && !defined $content_length) {
            my $buffer = "" x 1024;
            while ($socket->read($buffer, 1024)) {
              $content .= $buffer;
            }
            last;
          }
          else {
            next;
          }
        }
        else {
          if ($header =~ /transfer-encoding\s*:\s*chunked/i) {
            $chunked = 1;
          }
          elsif ($header =~ /content-length\s*:\s*(\d+)/i) {
            $content_length = 0 + $1;
          }
          $header .= $line;
        }
      }
      elsif ($chunked && $line =~ /^([[:xdigit:]]+)(;.*)?\r\n$/s) {
        my $original_size = $1;
        my $size          = hex($1);
        my $ext           = $2;
        my $buffer        = '';
        my $read          = $socket->read($buffer, $size + 2);
        my $chunk_content = substr($buffer, 0, $size);
        my $chunk         = {
          size_raw    => $original_size,
          size        => $size,
          size_length => length($chunk_content),
          size_actual => $read,
          content     => $verbose ? b64_encode($chunk_content) : '<omit>',
          content_md5 => md5_sum($chunk_content),
          ext         => $ext,
          eol         => substr($buffer, $size, 2),
        };
        $content .= $chunk_content;
        push @chunks, $chunk;

        if ($size == 0) {
          last;
        }
      }
      else {
        die "unexpected line: $line\n";
        last;
      }
    }
    1;
  };
  warn $@ unless $ok;

  my $sum = 0;
  foreach my $chunk (@chunks) {
    $sum += $chunk->{size_length};
  }

  return {
    url     => $url_opt,
    chunks  => \@chunks,
    header  => $verbose ? [split(/(\r\n)/, $header)] : [split(/\r\n/, $header)],
    content => $verbose ? b64_encode($content) : '<omit>',
    chunks_content_length => $sum,
    content_length        => length($content),
    content_md5           => md5_sum($content),
  };
}

