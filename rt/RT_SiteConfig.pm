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

# Keep redirect canonicalization disabled behind the Caddy FastCGI gateway.
# WebURL still defines the canonical URL for RT links and inline-edit features.
my $rt_web_url = $ENV{'RT_WEB_URL'} || 'http://localhost:8088/';
$rt_web_url .= '/' unless $rt_web_url =~ m{/$};
Set($WebURL, $rt_web_url);
# Browsers reject Secure session cookies on plain HTTP. Preserve Secure
# cookies automatically when RT is served over HTTPS.
Set($WebSecureCookies, $rt_web_url =~ m{^https://}i ? 1 : 0);
# RT does not derive these settings from WebURL.
require URI;
my $rt_uri = URI->new($rt_web_url);
Set($WebDomain, $rt_uri->host);
Set($WebPort, $rt_uri->port);
Set($WebPath, $rt_uri->path eq '/' ? '' : $rt_uri->path);
Set($CanonicalizeRedirectURLs, 0);
Set($CanonicalizeURLsInFeeds, 0);

1;
