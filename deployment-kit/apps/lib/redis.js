'use strict';

const net = require('net');

function encodeCommand(args) {
  let out = `*${args.length}\r\n`;
  for (const arg of args) {
    const value = String(arg);
    out += `$${Buffer.byteLength(value)}\r\n${value}\r\n`;
  }
  return out;
}

class RespParser {
  constructor(buffer) {
    this.buffer = buffer;
    this.offset = 0;
  }

  readLine() {
    const end = this.buffer.indexOf('\r\n', this.offset);
    if (end === -1) {
      throw new Error('invalid redis response');
    }
    const line = this.buffer.slice(this.offset, end);
    this.offset = end + 2;
    return line;
  }

  parse() {
    const prefix = this.buffer[this.offset++];
    if (!prefix) {
      throw new Error('empty redis response');
    }

    if (prefix === '+') {
      return this.readLine();
    }

    if (prefix === '-') {
      throw new Error(this.readLine());
    }

    if (prefix === ':') {
      return Number(this.readLine());
    }

    if (prefix === '$') {
      const length = Number(this.readLine());
      if (length === -1) {
        return null;
      }
      const value = this.buffer.slice(this.offset, this.offset + length);
      this.offset += length + 2;
      return value;
    }

    if (prefix === '*') {
      const length = Number(this.readLine());
      if (length === -1) {
        return null;
      }
      const result = [];
      for (let index = 0; index < length; index += 1) {
        result.push(this.parse());
      }
      return result;
    }

    throw new Error(`unsupported redis response prefix: ${prefix}`);
  }
}

function parseRedisUrl(redisUrl) {
  const parsed = new URL(redisUrl);
  return {
    host: parsed.hostname,
    port: Number(parsed.port || 6379),
    password: parsed.password ? decodeURIComponent(parsed.password) : '',
    database: parsed.pathname && parsed.pathname !== '/' ? parsed.pathname.slice(1) : '',
  };
}

class RedisStore {
  constructor(redisUrl, prefix = 'deployment-kit:entity') {
    this.options = parseRedisUrl(redisUrl);
    this.prefix = prefix;
  }

  async command(args) {
    const socket = net.createConnection({
      host: this.options.host,
      port: this.options.port,
      timeout: 2500,
    });

    return new Promise((resolve, reject) => {
      const chunks = [];
      let settled = false;
      const expectedResponses = 1 + (this.options.password ? 1 : 0) + (this.options.database ? 1 : 0);

      const fail = (error) => {
        if (!settled) {
          settled = true;
          socket.destroy();
          reject(error);
        }
      };

      const tryResolve = () => {
        if (settled) {
          return;
        }

        try {
          const parser = new RespParser(Buffer.concat(chunks).toString('utf8'));
          let value;
          for (let index = 0; index < expectedResponses; index += 1) {
            value = parser.parse();
          }
          settled = true;
          socket.destroy();
          resolve(value);
        } catch (error) {
          if (!String(error.message || '').includes('invalid redis response')) {
            fail(error);
          }
        }
      };

      socket.on('connect', () => {
        const commands = [];
        if (this.options.password) {
          commands.push(['AUTH', this.options.password]);
        }
        if (this.options.database) {
          commands.push(['SELECT', this.options.database]);
        }
        commands.push(args);
        socket.write(commands.map(encodeCommand).join(''));
      });

      socket.on('data', (chunk) => {
        chunks.push(chunk);
        tryResolve();
      });
      socket.on('timeout', () => fail(new Error('redis timeout')));
      socket.on('error', fail);
    });
  }

  async put(item) {
    await this.command(['SET', `${this.prefix}:${item.id}`, JSON.stringify(item)]);
    await this.command(['LPUSH', `${this.prefix}:ids`, item.id]);
    return item;
  }

  async get(id) {
    const raw = await this.command(['GET', `${this.prefix}:${id}`]);
    return raw ? JSON.parse(raw) : null;
  }

  async update(id, patch) {
    const current = await this.get(id);
    if (!current) {
      return null;
    }
    const updated = { ...current, ...patch, id, updatedAt: new Date().toISOString() };
    await this.command(['SET', `${this.prefix}:${id}`, JSON.stringify(updated)]);
    return updated;
  }

  async list(limit = 20) {
    const ids = await this.command(['LRANGE', `${this.prefix}:ids`, 0, limit - 1]);
    const result = [];
    for (const id of ids || []) {
      const entity = await this.get(id);
      if (entity) {
        result.push(entity);
      }
    }
    return result;
  }
}

class MemoryStore {
  constructor() {
    this.items = new Map();
    this.ids = [];
  }

  async put(item) {
    this.items.set(item.id, item);
    this.ids.unshift(item.id);
    return item;
  }

  async get(id) {
    return this.items.get(id) || null;
  }

  async update(id, patch) {
    const current = await this.get(id);
    if (!current) {
      return null;
    }
    const updated = { ...current, ...patch, id, updatedAt: new Date().toISOString() };
    this.items.set(id, updated);
    return updated;
  }

  async list(limit = 20) {
    return this.ids.slice(0, limit).map((id) => this.items.get(id)).filter(Boolean);
  }
}

function createStore(redisUrl, prefix) {
  if (!redisUrl || redisUrl.startsWith('memory://')) {
    return new MemoryStore();
  }

  return new RedisStore(redisUrl, prefix);
}

module.exports = {
  MemoryStore,
  RedisStore,
  createStore,
};
