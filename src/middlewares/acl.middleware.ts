import type { NextFunction, Request, Response } from "express"

import { ApiError } from "../utils/api.error.js";
import type { Role } from "../types/User.js";

export const verifyRole =
  (roles: Role[]) =>
  (req: Request, res: Response, next: NextFunction) => {

    const role = res.locals.user?.role as Role;

    if (!role || !roles.includes(role)) {
      throw new ApiError(
        403,
        "You do not have sufficient permissions to perform this action."
      );
    }
    next();
};