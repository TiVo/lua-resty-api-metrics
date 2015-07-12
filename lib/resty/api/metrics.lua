_M = { _VERSION = "1.0" }

function log_request(redis_connection, redis_pool_size, ip, uri_parameters, log_level)
    if not uri_parameters.api_key then
        return
    end

    if string.len(uri_parameters.api_key) == 32 then
        local date = os.date("%Y-%m-%d")
        redis_connection:init_pipeline()

        redis_connection:sadd("KEYS:" .. date .. "", uri_parameters.api_key)
        redis_connection:incr("REQUESTS_DAY:" .. date .. "")
        redis_connection:incr("REQUESTS_KEY_DAY:" .. date .. ":" .. uri_parameters.api_key .. "")
        redis_connection:pfadd("IPS_DAY:" .. date .. "", ip)
        redis_connection:pfadd("IPS_KEY_DAY:" .. date .. ":" .. uri_parameters.api_key .. "", ip)

        local results, error = redis_connection:commit_pipeline()
        if not results then
            ngx.log("failed to commit the pipelined requests: ", error)
            return
        end

        local ok, error = redis_connection:set_keepalive(60000, redis_pool_size)
        if not ok then
            ngx.log(log_level, "failed to set keepalive: ", error)
            return
        end
    else
        return
    end
end

function _M.log(config)
    local log_level = config.log_level or ngx.ERR

    if not config.connection then
        local ok, redis = pcall(require, "resty.redis")
        if not ok then
            ngx.log(log_level, "failed to require redis")
            return
        end

        local redis_config = config.redis_config or {}
        redis_config.timeout = redis_config.timeout or 1
        redis_config.host = redis_config.host or "127.0.0.1"
        redis_config.port = redis_config.port or 6379
        redis_config.pool_size = redis_config.pool_size or 100

        local redis_connection = redis:new()
        redis_connection:set_timeout(redis_config.timeout * 1000)

        local ok, error = redis_connection:connect(redis_config.host, redis_config.port)
        if not ok then
            ngx.log(log_level, "failed to connect to redis: ", error)
            return
        end

        config.redis_config = redis_config
        config.connection = redis_connection
    end

    local connection = config.connection
    local redis_pool_size = config.redis_config.pool_size
    local ip = config.ip or ngx.var.remote_addr
    local uri_parameters = ngx.req.get_uri_args()

    local response, error = log_request(connection, redis_pool_size, ip, uri_parameters, log_level)
    return
end

return _M