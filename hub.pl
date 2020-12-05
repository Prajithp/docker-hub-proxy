#!/usr/bin/env perl

use Mojolicious::Lite;
use Cache::FileCache;
use Syntax::Keyword::Try;

helper 'registry' => sub { 'registry.docker.io' };
helper 'authUrl'  => sub { 'https://auth.docker.io/token' };
helper 'cache'    => sub { state $cache = Cache::FileCache->new; };

$ENV{MOJO_MAX_MESSAGE_SIZE} = 524288000;
app->config(hypnotoad => { clients => $ENV{HYPNOTOAD_CLIENTS} // 100 });

helper authToken => sub {
    my ($self, $repo) = @_;

    my $cached_token = $self->cache->get($repo);
    if (! defined $cached_token ) {
        app->log->info("Requesting for token");
        my $url    = sprintf("%s?service=%s&scope=repository:%s:pull", $self->authUrl, $self->registry, $repo);
        my $tx     = $self->ua->get($url);
        my $res    = $tx->result->json;

        my $token  = $res->{'token'};
        my $ttl    = $res->{'expires_in'};
        $self->cache->set($repo, $token, $ttl);
        
        return $token;   
    }
    app->log->info("Token found in the cache");
    return $cached_token;
};

helper authHeader => sub { 
    my ($self, $repo, $type) = @_;

    my $header = { Authorization => undef, Accept => $type };
    my $token  = $self->authToken($repo); 
    $header->{'Authorization'} = 'Bearer ' . $token;
    return $header;
};

get '/' => sub {
  my $c = shift;
  
  $c->render(json => ['ok']);
};

under '/v2';
get '/' => sub {
  my $c = shift;

  $c->render(json => ['ok']);
};

any '/*name/manifests/*ref' => sub {
    my $c = shift;
    
    $c->render_later;
    
    my $name = $c->param('name');
    my $ref  = $c->param('ref');

    my $imageName = $name;
    if (index ($name, '/') == -1 ) {
       $imageName = 'library/' . $name;
    }

    my $auth_head = $c->authHeader($imageName, 'application/vnd.docker.distribution.manifest.v2+json');
    my $url = sprintf("https://%s/v2/%s/manifests/%s", 'registry-1.docker.io', $imageName, $ref);
    my $tx  = $c->ua->get($url, $auth_head);

    my $response = {};
    my $status   = 404;
    if ($tx->res->code == 200) {
        $response = $tx->res->json;
        $status = 200;
        my $mediaType = $response->{'mediaType'};
        $c->res->headers->content_type($mediaType);        
    }
    return $c->render(json => $response, status => $status);      
};

get '/*name/blobs/:ref' => sub {
    my $c = shift;
       
    $c->render_later;
    $c->inactivity_timeout(0);

    my $name = $c->param('name');
    my $ref  = $c->param('ref');
    
    my $imageName = $name;
    if (index ($name, '/') == -1 ) {
       $imageName = 'library/' . $name;
    }
    my $auth_head = $c->authHeader($imageName, 'application/vnd.docker.distribution.manifest.v2+json');
    my $url = sprintf("https://%s/v2/%s/blobs/%s", 'registry-1.docker.io', $imageName, $ref);
    my $tx  = $c->app->ua->get($url, $auth_head);

    if (my $location = $tx->res->headers->location) {
        $c->res->code(200);
        $c->res->headers->content_type("application/octet-stream"); 

        my $length = $c->app->ua->head($location)->res->headers->content_length;
        $c->res->headers->content_length($length);

        $c->app->ua->max_response_size(0);
        $c->app->log->info("calling remote location $location");

        my $d_tx = $c->app->ua->build_tx('GET' => $location);
        $d_tx->res->content->unsubscribe('read')->on(
            read => sub {
                my (undef, $chunk) = @_;
                if ($chunk) {
                    try {
                        return $c->write($chunk, sub { return });
                    }
                    catch {
			 $c->app->log->info("Writing chunk failed: $@");
                         $d_tx->res->content->unsubscribe('read');
                    }
                }
            }
        );
        $c->app->ua->start_p($d_tx)->then(sub  {
             my $tx = shift;
        })->catch(sub  {
            my $err = shift;
            warn "Connection error: $err";
        })->wait;
    }
};
app->start;
