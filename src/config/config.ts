import { configDotenv } from "dotenv";

configDotenv();

const config = {
    port: process.env.PORT 
}

export default config;