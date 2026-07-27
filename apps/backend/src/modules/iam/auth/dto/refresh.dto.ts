import { IsString, IsUUID } from 'class-validator';

export class RefreshDto {
  @IsUUID()
  sessionId!: string;

  @IsString()
  secret!: string;
}
