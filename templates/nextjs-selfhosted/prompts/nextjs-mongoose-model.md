# Next.js Mongoose Model Template

## Variables
- `{{MODEL_NAME}}` — PascalCase name, e.g. `Product`, `Order`
- `{{FIELDS}}` — field list with types and constraints
- `{{RELATIONS}}` — optional refs to other models

## Prompt

Create a production-ready Mongoose model following this stack's conventions.

**Model name:** {{MODEL_NAME}}
**Fields:** {{FIELDS}}
**Relations:** {{RELATIONS}}

**Requirements:**

1. **File location:** `src/server/models/{{model-name}}.model.ts` (kebab-case filename)

2. **Structure:**
   ```ts
   import { Schema, model, models, type Model, type Types } from 'mongoose';

   export interface I{{MODEL_NAME}} {
     _id: Types.ObjectId;
     // ... fields with exact TS types
     createdAt: Date;
     updatedAt: Date;
     deletedAt: Date | null;
   }

   const {{modelName}}Schema = new Schema<I{{MODEL_NAME}}>(
     {
       // ... fields with validators, indexes, defaults
       deletedAt: { type: Date, default: null, index: true },
     },
     { timestamps: true }
   );

   // Indexes for queried fields
   {{modelName}}Schema.index({ field1: 1, deletedAt: 1 });

   // Hooks (if needed)
   {{modelName}}Schema.pre('save', function (next) { /* ... */ });

   // Instance methods (only if needed — prefer services)
   // {{modelName}}Schema.methods.someMethod = function () { /* ... */ };

   export const {{MODEL_NAME}}Model: Model<I{{MODEL_NAME}}> =
     models.{{MODEL_NAME}} || model<I{{MODEL_NAME}}>('{{MODEL_NAME}}', {{modelName}}Schema);
   ```

3. **Field rules:**
   - `required: true` for non-nullable fields
   - `unique: true` only for truly unique fields (email, slug)
   - `lowercase: true` for emails/slugs
   - `trim: true` for user-input strings
   - `enum` for constrained strings
   - `select: false` for sensitive fields (passwords, tokens)
   - `ref` for relations to other models
   - `index: true` for anything you query

4. **Always include:**
   - `timestamps: true` (gives `createdAt` + `updatedAt`)
   - `deletedAt` soft-delete field with index
   - Compound indexes for common queries (e.g. `{ userId: 1, deletedAt: 1 }`)

5. **Avoid:**
   - Business logic in hooks (use services)
   - Virtual fields that require DB queries
   - Middleware that calls external services

**Output:** Just the model file. No explanation.
