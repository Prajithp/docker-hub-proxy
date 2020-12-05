# docker-hub-proxy
A caching proxy server for Docker hub based on Nginx and Perl Mojolicious. 
  Recently Docker hub introduced rate-limiting for pull requests. If you are using the free tier of Docker Hub, all your images will be subject to a pull request limit of 100 pulls per six hours, free plan authenticated accounts limited to 200 pulls per six hours.
  
## Installation
```
docker build -t dockerHubProxy .
docker run --rm -d -p 3000:8080 -ti dockerHubProxy:latest
```
```
apt-get install nginx
```
Once the nginx is installed, modify the hub.conf and copy to nginx conf.d/ directory and restart nginx service.




