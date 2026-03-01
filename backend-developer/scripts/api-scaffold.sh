#!/usr/bin/env bash
# api-scaffold.sh - Generate REST API resource scaffolding
# Usage: ./api-scaffold.sh <resource-name> [--dir src] [--orm prisma|drizzle]
#
# Generates: route, service, validation schema, test file

set -euo pipefail

RESOURCE="${1:?Usage: $0 <resource-name> [--dir src] [--orm prisma|drizzle]}"
BASE_DIR="src"
ORM="prisma"

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) BASE_DIR="$2"; shift 2 ;;
    --orm) ORM="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Naming conventions
SINGULAR="$RESOURCE"
PLURAL="${RESOURCE}s"
# Portable PascalCase: split on hyphens, capitalize first letter of each part
PASCAL=$(echo "$RESOURCE" | awk -F'-' '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); printf "%s", $1; for(i=2;i<=NF;i++) printf "%s", $i; print ""}')
# camelCase: lowercase the first letter of PascalCase
CAMEL=$(echo "$PASCAL" | awk '{print tolower(substr($0,1,1)) substr($0,2)}')

ROUTE_DIR="$BASE_DIR/routes"
SERVICE_DIR="$BASE_DIR/services"
SCHEMA_DIR="$BASE_DIR/schemas"
TEST_DIR="$BASE_DIR/__tests__"

mkdir -p "$ROUTE_DIR" "$SERVICE_DIR" "$SCHEMA_DIR" "$TEST_DIR"

echo "Generating API resource: $PASCAL"
echo "  Route:      $ROUTE_DIR/${PLURAL}.route.ts"
echo "  Service:    $SERVICE_DIR/${PLURAL}.service.ts"
echo "  Schema:     $SCHEMA_DIR/${PLURAL}.schema.ts"
echo "  Test:       $TEST_DIR/${PLURAL}.test.ts"
echo ""

# Validation Schema
cat > "$SCHEMA_DIR/${PLURAL}.schema.ts" << EOF
import { z } from 'zod';

export const create${PASCAL}Schema = z.object({
  name: z.string().min(1).max(200),
  // Add more fields as needed
});

export const update${PASCAL}Schema = create${PASCAL}Schema.partial();

export const ${CAMEL}QuerySchema = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  sort: z.enum(['asc', 'desc']).default('desc'),
  search: z.string().max(200).optional(),
});

export type Create${PASCAL}Input = z.infer<typeof create${PASCAL}Schema>;
export type Update${PASCAL}Input = z.infer<typeof update${PASCAL}Schema>;
export type ${PASCAL}Query = z.infer<typeof ${CAMEL}QuerySchema>;
EOF

# Service
cat > "$SERVICE_DIR/${PLURAL}.service.ts" << EOF
import { prisma } from '../lib/prisma';
import type { Create${PASCAL}Input, Update${PASCAL}Input, ${PASCAL}Query } from '../schemas/${PLURAL}.schema';
import { NotFoundError } from '../lib/errors';

export class ${PASCAL}Service {
  async findAll(query: ${PASCAL}Query) {
    const { cursor, limit, sort, search } = query;

    const items = await prisma.${CAMEL}.findMany({
      take: limit + 1,
      ...(cursor && { cursor: { id: cursor }, skip: 1 }),
      orderBy: { createdAt: sort },
      ...(search && {
        where: { name: { contains: search, mode: 'insensitive' } },
      }),
    });

    const hasMore = items.length > limit;
    const data = hasMore ? items.slice(0, limit) : items;

    return {
      data,
      pageInfo: {
        hasNextPage: hasMore,
        endCursor: data.at(-1)?.id ?? null,
      },
    };
  }

  async findById(id: string) {
    const item = await prisma.${CAMEL}.findUnique({ where: { id } });
    if (!item) throw new NotFoundError('${PASCAL} not found');
    return item;
  }

  async create(input: Create${PASCAL}Input) {
    return prisma.${CAMEL}.create({ data: input });
  }

  async update(id: string, input: Update${PASCAL}Input) {
    await this.findById(id); // Ensure exists
    return prisma.${CAMEL}.update({ where: { id }, data: input });
  }

  async delete(id: string) {
    await this.findById(id); // Ensure exists
    await prisma.${CAMEL}.delete({ where: { id } });
  }
}

export const ${CAMEL}Service = new ${PASCAL}Service();
EOF

# Route
cat > "$ROUTE_DIR/${PLURAL}.route.ts" << EOF
import { Router } from 'express';
import { ${CAMEL}Service } from '../services/${PLURAL}.service';
import { create${PASCAL}Schema, update${PASCAL}Schema, ${CAMEL}QuerySchema } from '../schemas/${PLURAL}.schema';
import { validate } from '../middleware/validate';
import { asyncHandler } from '../lib/async-handler';

const router = Router();

// GET /api/${PLURAL}
router.get('/', asyncHandler(async (req, res) => {
  const query = ${CAMEL}QuerySchema.parse(req.query);
  const result = await ${CAMEL}Service.findAll(query);
  res.json(result);
}));

// GET /api/${PLURAL}/:id
router.get('/:id', asyncHandler(async (req, res) => {
  const item = await ${CAMEL}Service.findById(req.params.id);
  res.json({ data: item });
}));

// POST /api/${PLURAL}
router.post('/', validate(create${PASCAL}Schema), asyncHandler(async (req, res) => {
  const item = await ${CAMEL}Service.create(req.body);
  res.status(201).json({ data: item });
}));

// PATCH /api/${PLURAL}/:id
router.patch('/:id', validate(update${PASCAL}Schema), asyncHandler(async (req, res) => {
  const item = await ${CAMEL}Service.update(req.params.id, req.body);
  res.json({ data: item });
}));

// DELETE /api/${PLURAL}/:id
router.delete('/:id', asyncHandler(async (req, res) => {
  await ${CAMEL}Service.delete(req.params.id);
  res.status(204).end();
}));

export { router as ${CAMEL}Router };
EOF

# Test
cat > "$TEST_DIR/${PLURAL}.test.ts" << EOF
import { describe, it, expect, beforeEach } from 'vitest';
import request from 'supertest';
import { app } from '../app';
import { prisma } from '../lib/prisma';

describe('${PASCAL} API', () => {
  beforeEach(async () => {
    await prisma.${CAMEL}.deleteMany();
  });

  describe('POST /api/${PLURAL}', () => {
    it('creates a ${SINGULAR} and returns 201', async () => {
      const res = await request(app)
        .post('/api/${PLURAL}')
        .send({ name: 'Test ${PASCAL}' })
        .expect(201);

      expect(res.body.data).toMatchObject({ name: 'Test ${PASCAL}' });
      expect(res.body.data.id).toBeDefined();
    });

    it('rejects invalid input with 400', async () => {
      await request(app)
        .post('/api/${PLURAL}')
        .send({ name: '' })
        .expect(400);
    });
  });

  describe('GET /api/${PLURAL}', () => {
    it('returns paginated list', async () => {
      await prisma.${CAMEL}.createMany({
        data: Array.from({ length: 5 }, (_, i) => ({ name: \`Item \${i}\` })),
      });

      const res = await request(app)
        .get('/api/${PLURAL}?limit=3')
        .expect(200);

      expect(res.body.data).toHaveLength(3);
      expect(res.body.pageInfo.hasNextPage).toBe(true);
    });
  });

  describe('GET /api/${PLURAL}/:id', () => {
    it('returns 404 for non-existent ${SINGULAR}', async () => {
      await request(app)
        .get('/api/${PLURAL}/non-existent-id')
        .expect(404);
    });
  });

  describe('DELETE /api/${PLURAL}/:id', () => {
    it('deletes and returns 204', async () => {
      const item = await prisma.${CAMEL}.create({ data: { name: 'To Delete' } });

      await request(app)
        .delete(\`/api/${PLURAL}/\${item.id}\`)
        .expect(204);

      const deleted = await prisma.${CAMEL}.findUnique({ where: { id: item.id } });
      expect(deleted).toBeNull();
    });
  });
});
EOF

# Make scripts executable
chmod +x "$0" 2>/dev/null || true

echo "Done! Files generated:"
echo "  $SCHEMA_DIR/${PLURAL}.schema.ts"
echo "  $SERVICE_DIR/${PLURAL}.service.ts"
echo "  $ROUTE_DIR/${PLURAL}.route.ts"
echo "  $TEST_DIR/${PLURAL}.test.ts"
echo ""
echo "Next steps:"
echo "  1. Add Prisma model for '$PASCAL' in schema.prisma"
echo "  2. Run: npx prisma migrate dev --name add_${PLURAL}"
echo "  3. Register route in app.ts: app.use('/api/${PLURAL}', ${CAMEL}Router)"
echo "  4. Run tests: pnpm vitest run $TEST_DIR/${PLURAL}.test.ts"
