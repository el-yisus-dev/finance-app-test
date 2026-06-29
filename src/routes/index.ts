import express, { type Router, type Express} from 'express'


const routerAPI = (app: Express) => {

    const router: Router = express.Router()

    app.get("/", (req, res) => {
        res.json({
            "status": "exito",
            data: {
                message: "First steps master in the app u.ur"
            }
        })
    })

    app.use("/api/v1", router);

}

export {
    routerAPI
};