import type { Request, Response, NextFunction } from "express"

import type { ZodType } from "zod"  

import { ApiError } from "../utils/api.error.js"

export const validate = (schema: ZodType, property: "body" | "params" | "query" = "body") => {
  return (req: Request, res: Response, next: NextFunction) => {

    const result = schema.safeParse(req[property])

    if (!result.success) {
      const errors = result.error.issues.map(issue => ({
        field: issue.path.join("."),
        message: issue.message
      }))

      throw new ApiError(400, "Validation error", errors)
    }

    if (property === "body") {
      req.body = result.data;
    } else {
      Object.keys(req[property]).forEach(key => delete req[property][key]);
      Object.assign(req[property], result.data);
    }
    next()
  }
}