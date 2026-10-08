# Request Tracker site configuration managed by this repository.
# Secrets are supplied through the container environment; do not commit them here.

Set($rtname, $ENV{'RT_NAME'} || 'infrastructure');
Set($Organization, $ENV{'RT_ORGANIZATION'} || 'example.invalid');

Set($DatabaseType, 'Pg');
Set($DatabaseHost, 'rt-db');
Set($DatabasePort, '5432');
Set($DatabaseUser, $ENV{'RT_DB_USER'} || 'rt');
Set($DatabasePassword, $ENV{'RT_DB_PASSWORD'});
Set($DatabaseName, $ENV{'RT_DB_NAME'} || 'rt');
Set($DatabaseAdmin, $ENV{'RT_DB_USER'} || 'rt');

# Leave URL canonicalization disabled so direct LAN access and a configured
# reverse-proxy hostname can both be used during initial deployment.
my $rt_web_url = $ENV{'RT_WEB_URL'} || 'http://localhost:8088/';
$rt_web_url .= '/' unless $rt_web_url =~ m{/$};
Set($WebURL, $rt_web_url);
Set($CanonicalizeRedirectURLs, 1);
Set($CanonicalizeURLsInFeeds, 0);

1;
