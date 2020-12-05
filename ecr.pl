#!/usr/bin/env perl
use Mojolicious::Lite;
use Paws ();
use Paws::Credential::File;
use Cpanel::JSON::XS;

Paws->default_config->immutable(1);
Paws->preload_service('ECR');

plugin 'DefaultHelpers';

helper paws => sub {
    state $paws = Paws->new(
       config => {
           region => 'ap-south-1',
           credentials => Paws::Credential::File->new(
                profile => 'prod'
           ),
       }
    );
};

helper ecr => sub {
    state $client = $_[0]->paws->service('ECR');
};

helper 'docker.manifests' => sub {
    my ($c, $name, $ref) = @_;

    my $imageStruct = {};
    if ($ref =~ m/^\w+:([A-Fa-f0-9]+$)/) {
        $imageStruct->{'ImageDigest'} = $ref;
    }   
    else {
       $imageStruct->{'ImageTag'} = $ref;
    }

    my $images = $c->ecr->BatchGetImage(ImageIds => [$imageStruct], RepositoryName => $name)->Images;
    if (my $image = $images->[0]) {
        return decode_json($image->ImageManifest);
    }

    return undef;
};

under '/v2/'; 

get '/' => sub {
  my $c = shift;

  $c->render(json => ['ok']);
};

any '/*name/manifests/*ref' => sub {
    my $c = shift;

    $c->render_later;

    my $name = $c->param('name');
    my $ref  = $c->param('ref');

    my $image  = $c->docker->manifests($name, $ref);
    my $status = $image ? 200 : 404;
   
    if ($c->req->method eq 'HEAD') {
        return $c->rendered($status);
    }

    return $c->render(json => {}, status => $status) unless $image;

    my $mediaType = $image->{'mediaType'};
    $c->res->headers->content_type($mediaType);
    
    return $c->render(json => $image, status => $status);
};

get '/*name/blobs/:ref' => sub {
    my $c = shift;
    
    $c->render_later;
    
    my $name = $c->param('name');
    my $ref  = $c->param('ref');
   
    my $url = $c->ecr->GetDownloadUrlForLayer(LayerDigest => $ref, RepositoryName => $name);
    $c->res->headers->header('Location' => $url->DownloadUrl);
    $c->res->headers->header('Docker-Content-Digest' => $url->LayerDigest);
    return $c->rendered(307);
};

get '/*name/tags/list' => sub {
    my $c = shift;
    my $name = $c->param('name');

    my $imagesResponse = $c->ecr->DescribeImages(RepositoryName => $name);
    my $imageDetails = $imagesResponse->ImageDetails;
  
    if (my $imageDetail = $imageDetails->[0]) {     
       my $response = {
           name => $name,
           tags => $imageDetail->imageDetail
       };
       return $c->render(json => $response);
    }

    return $c->rendered(404);    
};

app->start;
