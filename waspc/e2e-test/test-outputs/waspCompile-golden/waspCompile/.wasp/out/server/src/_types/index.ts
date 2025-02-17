import prisma from "../dbClient.js"
import { type _Entity } from "./taggedEntities"

export * from "./taggedEntities"

export type Query<Entities extends _Entity[], Input, Output> = Operation<Entities, Input, Output>

export type Action<Entities extends _Entity[], Input, Output> = Operation<Entities, Input, Output>

type Operation<Entities extends _Entity[], Input, Output> = (
  args: Input,
  context: Expand<OperationContext<Entities>>,
) => Promise<Output>

type OperationContext<Entities extends _Entity[]> = {
  entities: Expand<EntityMap<Entities>>
}

type EntityMap<Entities extends _Entity[]> = {
  [EntityName in Entities[number]["_entityName"]]: PrismaDelegate[EntityName]
}

type PrismaDelegate = {
}

// This is a helper type used exclusively for DX purposes. It's a No-op for the
// compiler, but expands the type's representatoin in IDEs (i.e., inlines all
// type constructors) to make it more readable for the user.
//
// Check this SO answer for details: https://stackoverflow.com/a/57683652
type Expand<T extends object> = T extends infer O ? { [K in keyof O]: O[K] } : never
