import { NotificationDispatchService } from './notification-dispatch.service';
import { PrismaService } from '../../common/prisma/prisma.service';
import { MailerService } from '../../common/mailer/mailer.service';

/** FUNCTIONAL_REQUIREMENTS.md §15: notifica alertas abiertas, evita duplicados. */
describe('NotificationDispatchService', () => {
  const openAlert = {
    id: 'alert-1',
    organizationId: 'org-1',
    alertType: 'threshold',
    status: 'open',
    openedAt: new Date(),
  };

  function buildDeps(params: {
    alerts?: Array<typeof openAlert>;
    members?: Array<{ userId: string; roleCode: string; user: { email: string } }>;
    alreadyNotified?: boolean;
    sendOk?: boolean;
  }) {
    const notificationLog = {
      findUnique: jest.fn().mockResolvedValue(params.alreadyNotified ? { id: 'log-1' } : null),
      create: jest.fn().mockResolvedValue({}),
    };
    const tx = {
      member: { findMany: jest.fn().mockResolvedValue(params.members ?? []) },
      notificationLog,
    };
    const prisma = {
      alert: { findMany: jest.fn().mockResolvedValue(params.alerts ?? [openAlert]) },
      runInTenantContext: jest.fn(async (_ctx: unknown, fn: (tx: unknown) => unknown) => fn(tx)),
    } as unknown as PrismaService;

    const mailer = {
      send: jest.fn().mockResolvedValue({ ok: params.sendOk ?? true }),
    } as unknown as jest.Mocked<MailerService>;

    return { prisma, mailer, tx, notificationLog };
  }

  it('notifica a los roles destinatarios (org_admin/technician/operator) resueltos por la query de member', async () => {
    // El filtro de rol (`roleCode: { in: [...] }`) lo aplica la query real a
    // `member` — este mock ya simula el resultado *después* de ese filtro
    // (readonly nunca llegaría aquí en producción); lo que este test verifica
    // es que la query se construye con ese filtro y que se notifica a cada
    // destinatario que devuelve.
    const { prisma, mailer, tx } = buildDeps({
      members: [
        { userId: 'user-admin', roleCode: 'org_admin', user: { email: 'admin@example.com' } },
        { userId: 'user-tech', roleCode: 'technician', user: { email: 'tech@example.com' } },
      ],
    });
    const service = new NotificationDispatchService(prisma, mailer);
    await service.scan();

    expect(prisma.alert.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { status: { not: 'resolved' } } }),
    );
    expect(tx.member.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          roleCode: { in: ['org_admin', 'technician', 'operator'] },
        }),
      }),
    );
    expect(mailer.send).toHaveBeenCalledTimes(2);
    expect(mailer.send).toHaveBeenCalledWith(expect.objectContaining({ to: 'admin@example.com' }));
    expect(mailer.send).toHaveBeenCalledWith(expect.objectContaining({ to: 'tech@example.com' }));
  });

  it('no reenvía si ya existe una fila en notification_log para esa alerta+destinatario', async () => {
    const { prisma, mailer } = buildDeps({
      members: [
        { userId: 'user-admin', roleCode: 'org_admin', user: { email: 'admin@example.com' } },
      ],
      alreadyNotified: true,
    });
    const service = new NotificationDispatchService(prisma, mailer);
    await service.scan();

    expect(mailer.send).not.toHaveBeenCalled();
  });

  it('registra el resultado en notification_log tras enviar', async () => {
    const { prisma, mailer, tx } = buildDeps({
      members: [
        { userId: 'user-admin', roleCode: 'org_admin', user: { email: 'admin@example.com' } },
      ],
      sendOk: true,
    });
    const service = new NotificationDispatchService(prisma, mailer);
    await service.scan();

    expect(tx.notificationLog.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          alertId: 'alert-1',
          recipientUserId: 'user-admin',
          status: 'sent',
        }),
      }),
    );
  });

  it('excluye alertas resueltas: solo procesa lo que devuelve la query ya filtrada', async () => {
    const { prisma, mailer } = buildDeps({ alerts: [] });
    const service = new NotificationDispatchService(prisma, mailer);
    await service.scan();

    expect(prisma.runInTenantContext).not.toHaveBeenCalled();
    expect(mailer.send).not.toHaveBeenCalled();
  });
});
