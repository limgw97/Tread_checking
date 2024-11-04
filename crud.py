from sqlalchemy import create_engine, MetaData, Table, Column, Integer, LargeBinary, Boolean, String
from sqlalchemy.sql import select, insert, update
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.future import select as async_select

DATABASE_URL = "postgresql+asyncpg://neondb_owner:4LloSGATmDV8@ep-floral-wave-a1upn41u.ap-southeast-1.aws.neon.tech/neondb"

engine = create_async_engine(DATABASE_URL, echo=True)
async_session = sessionmaker(
    engine, expire_on_commit=False, class_=AsyncSession
)
metadata = MetaData()

input_data = Table(
    'input_data', metadata,
    Column('id', Integer, primary_key=True, autoincrement=True),
    Column('user_id', String(12), nullable=False),
    Column('image_data', LargeBinary, nullable=False),
    Column('state', Boolean, nullable=False)
)

async def get_async_session():
    async with async_session() as session:
        yield session

async def add_input_data(user_id: str, image_data: bytes, state: bool, session: AsyncSession):
    async with session.begin():
        stmt = insert(input_data).values(user_id=user_id, image_data=image_data, state=state)
        await session.execute(stmt)


async def get_input_data(user_id: int):
    async with async_session() as session:
        async with session.begin():
            stmt = async_select(input_data).where(input_data.c.user_id == user_id)
            result = await session.execute(stmt)
            return result.fetchall()

async def update_input_data_state(id: int, state: bool):
    async with async_session() as session:
        async with session.begin():
            stmt = update(input_data).where(input_data.c.id == id).values(state=state)
            await session.execute(stmt)


