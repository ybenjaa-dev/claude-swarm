# BullMQ Background Job Template

## Variables
- `{{JOB_NAME}}` — e.g. `sendEmail`, `processUpload`, `generateReport`
- `{{PAYLOAD}}` — job data shape
- `{{OPERATION}}` — what the job actually does

## Prompt

Create a BullMQ queue, worker, and producer helper for a background job.

**Job:** {{JOB_NAME}}
**Payload:** {{PAYLOAD}}
**Operation:** {{OPERATION}}

**Files to create:**

### 1. `src/server/queues/{{job-name}}.queue.ts`

```ts
import { Queue, QueueEvents } from 'bullmq';
import { redisConnection } from '@/lib/redis/client';

export interface {{JobName}}Payload {
  // ... typed payload fields
}

export const {{jobName}}Queue = new Queue<{{JobName}}Payload>('{{job-name}}', {
  connection: redisConnection,
  defaultJobOptions: {
    attempts: 3,
    backoff: { type: 'exponential', delay: 2000 },
    removeOnComplete: { age: 3600, count: 1000 },
    removeOnFail: { age: 24 * 3600 },
  },
});

export const {{jobName}}QueueEvents = new QueueEvents('{{job-name}}', {
  connection: redisConnection,
});

// Producer helper — call this from services
export async function enqueue{{JobName}}(payload: {{JobName}}Payload, opts?: { delay?: number; jobId?: string }) {
  return {{jobName}}Queue.add('{{job-name}}', payload, opts);
}
```

### 2. `src/server/workers/{{job-name}}.worker.ts`

```ts
import { Worker, type Job } from 'bullmq';
import { redisConnection } from '@/lib/redis/client';
import { logger } from '@/lib/logger';
import type { {{JobName}}Payload } from '@/server/queues/{{job-name}}.queue';

// Import the actual service that does the work
// import { {{feature}}Service } from '@/server/services/{{feature}}.service';

async function process(job: Job<{{JobName}}Payload>) {
  logger.info({ jobId: job.id, payload: job.data }, '{{JOB_NAME}} started');

  // ... do the work — call services, never HTTP

  logger.info({ jobId: job.id }, '{{JOB_NAME}} completed');
}

export const {{jobName}}Worker = new Worker<{{JobName}}Payload>(
  '{{job-name}}',
  process,
  {
    connection: redisConnection,
    concurrency: 5,
    limiter: { max: 10, duration: 1000 },
  }
);

{{jobName}}Worker.on('completed', (job) => {
  logger.info({ jobId: job.id }, 'Job completed');
});

{{jobName}}Worker.on('failed', (job, err) => {
  logger.error({ jobId: job?.id, err }, 'Job failed');
});

{{jobName}}Worker.on('error', (err) => {
  logger.error({ err }, 'Worker error');
});

// Graceful shutdown
const shutdown = async () => {
  await {{jobName}}Worker.close();
  process.exit(0);
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
```

### 3. `src/server/workers/index.ts` — boot all workers

Re-export all workers so a separate `worker` process can import them all:

```ts
export * from './{{job-name}}.worker';
// export * from './other.worker';
```

### 4. Separate entry point for workers: `worker.ts` (project root)

```ts
import 'dotenv/config';
import '@/server/workers';

console.log('✓ Workers started');
```

### 5. Usage from a service:

```ts
// In some service
import { enqueue{{JobName}} } from '@/server/queues/{{job-name}}.queue';

await enqueue{{JobName}}({ /* payload */ }, { delay: 5000 });
```

### 6. Docker compose addition:

```yaml
worker:
  build: .
  command: node dist/worker.js
  env_file: .env
  depends_on:
    - mongo
    - redis
  restart: unless-stopped
```

**Rules:**

1. **Workers run in a separate process** from the Next.js app — never in the request path
2. **Retries:** 3 attempts with exponential backoff
3. **Idempotency:** every job handler should be idempotent (safe to re-run)
4. **Job ID:** pass `opts.jobId` when you need to deduplicate (e.g. `user:123:welcome-email`)
5. **Never run workers inside Next.js server** — use a separate container/process
6. **Logging:** structured logs with `jobId` for traceability
7. **Graceful shutdown:** always close workers on SIGTERM/SIGINT
8. **Concurrency:** tune per job type (IO-heavy = higher, CPU-heavy = lower)

**Output:** All files listed above. Complete implementations.
