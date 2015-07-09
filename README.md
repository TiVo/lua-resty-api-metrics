## OpenResty Redis Backed API Metrics
This is a OpenResty Lua and Redis powered logger. We use it at The Movie Database (TMDb) to keep track of some basic metrics:

* unique api keys per day
* unique ips per day
* unique ips per api key per day
* total requests per day
* total requests per api key per day

We take advantage of Redis' HyperLogLog to store our unique counts. This makes it incredibly trivial to merge our daily totals and rollup uniques across multiple days, weeks and months.

It might seem odd to put this in a `access_by_lua` block but we need access to the cosocket API and `log_by_lua` doesn't provide this. Nginx also discourages putting a `content_by_lua` block inside a location where you use a proxy.

### OpenResty Prerequisite
You have to compile OpenResty with the `--with-http_realip_module` option.

### Needed in your nginx.conf
```
http {
    # http://serverfault.com/questions/331531/nginx-set-real-ip-from-aws-elb-load-balancer-address
    # http://serverfault.com/questions/331697/ip-range-for-internal-private-ip-of-amazon-elb
    set_real_ip_from            127.0.0.1;
    set_real_ip_from            10.0.0.0/8;
    set_real_ip_from            172.16.0.0/12;
    set_real_ip_from            192.168.0.0/16;
    real_ip_header              X-Forwarded-For;
    real_ip_recursive           on;
}
```

### Example OpenResty Site Config
```
# Location of this Lua package
lua_package_path "/opt/lua-resty-api-metrics/lib/?.lua;;";

upstream api {
    server unix:/run/api.sock;
}

server {
    listen 80;
    server_name api.dev;

    access_log  /var/log/openresty/api_access.log;
    error_log   /var/log/openresty/api_error.log;

    location / {
        access_by_lua '
            local api_metrics = require "resty.api.metrics"
	      	api_metrics.log { ip = ngx.var.remote_addr,
	                          log_level = ngx.NOTICE,
	                          redis_config = { host = "127.0.0.1", port = 6379, timeout = 1, pool_size = 100 } }
        ';

        proxy_set_header  Host               $host;
        proxy_set_header  X-Real-IP          $remote_addr;
        proxy_set_header  X-Forwarded-For    $remote_addr;

        proxy_connect_timeout  1s;
        proxy_read_timeout     30s;

        proxy_pass   http://api;
    }
}
```

### Config Values
You can customize some of the info we send back to collect by changing the following values:

* ip: The IP value to use as a identifier in Redis.
* log_level: Set an Nginx log level. All errors from this plugin will be dumped here
* redis_config: The Redis host, port, timeout and pool size
