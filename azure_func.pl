use strict;
use warnings;
use utf8;
use JSON::PP;
use Encode;

### タイムゾーン定義 / Azure Functionsでは必須。
BEGIN {
    $ENV{TZ} = "JST-9";
};

### 環境ファイル読み込み関数
sub read_from ($) {
    my ($envname) = @_;
    open my $fh, '<', $ENV{$envname} or die "$!";
    my $content = do {local $/; <$fh>};
    close $fh;
    return $content;
}

### 環境ファイル書き込み関数
sub write_to ($$) {
    my ($envname, $data) = @_;
    open my $fh, '>', $ENV{$envname} or die "$!";
    print $fh $data;
    close $fh;
}

### HTTPクエリパラメータ取得
sub param ($) {
    my $name = shift;
    my $key = sprintf "REQ_QUERY_%s", uc($name);
    Encode::decode_utf8($ENV{$key});
}

### HTTPヘッダ取得
sub header ($) {
    my $name = shift;
    my $key = sprintf "REQ_HEADERS_%s", uc($name);
    $ENV{$key};
}

### レスポンスを返す関数
sub res ($$$) {
    my ($code, $headers, $content) = @_;
    my $res = JSON::PP->new->utf8(1)->encode({
        status  => $code,
        headers => $headers,
        body    => $content
    });
    write_to(res => $res);
    exit;
}

### 外部コマンド実行
sub run ($;@) {
    my ($cmd, @opts) = @_;
    my @res = `$cmd @opts`;
    join "", @res;
}

1;