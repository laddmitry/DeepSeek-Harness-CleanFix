import { valueMap } from '@deepseek-ai/cosmokit'

// YAML JavaScript expressions have caller-defined result types.
type ExpressionEvaluator = (ctx: object, expr: string) => any
let expressionEvaluator: ExpressionEvaluator | undefined

/**
 * Evaluate an explicitly requested YAML JavaScript expression against its loader context.
 * Importing a loader with literal configuration does not compile dynamic code.
 * @param ctx - Context supplying expression bindings.
 * @param expr - JavaScript expression supplied by the configuration owner.
 * @returns The expression result.
 */
export const evaluate: ExpressionEvaluator = (ctx, expr) => {
  // eslint-disable-next-line no-new-func
  expressionEvaluator ??= new Function('ctx', 'expr', `
    with (ctx) {
      return eval(expr)
    }
  `) as ExpressionEvaluator
  return expressionEvaluator(ctx, expr)
}

/** Recursively replace YAML `!!js` expression nodes with evaluated values. */
export function interpolate(ctx: object, value: any) {
  if (isJsExpr(value)) {
    return evaluate(ctx, value.__jsExpr)
  } else if (!value || typeof value !== 'object') {
    return value
  } else if (Array.isArray(value)) {
    return value.map(item => interpolate(ctx, item))
  } else {
    return valueMap(value, item => interpolate(ctx, item))
  }
}

/** Return true when a value is a serialized loader JavaScript expression. */
export function isJsExpr(value: any): value is JsExpr {
  return value instanceof Object && '__jsExpr' in value
}

/** Serialized JavaScript expression produced by the include YAML tag. */
export interface JsExpr {
  __jsExpr: string
}
