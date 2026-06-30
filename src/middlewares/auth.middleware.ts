import type { Request, Response, NextFunction } from "express";

import { validateToken } from "../utils/Jwt.js";
import * as userRepository from "../repositories/user.repository.js";

import { ApiError } from "../utils/api.error.js";

export const verifyToken = async (req: Request, res: Response, next: NextFunction) => {
    const authHeader = req.headers.authorization;

    if (!authHeader?.startsWith("Bearer ")) {
        throw new ApiError(401, "Invalid token format");
    }

    const token = authHeader.split(' ')[1]


    if (token === null || token === undefined) {
        throw new ApiError(401, "Invalid Token");
    }

    const { sub } = validateToken(token)
    //@ts-ignore
    const user = await userRepository.findUserById(sub);
    
    if (user === null) {
        throw new ApiError(401, "Invalid Token");
    }
    
    const { role, username, email, id } = user;

    res.locals.user = { role, username, email, id };
    
    next()
}