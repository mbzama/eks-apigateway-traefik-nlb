docker rm -f mock-web
docker rmi -f mock-web

docker build -t mock-web .
docker run -p 3000:3000 mock-web
